# Example: adding a new server service in the flake-parts + options layout.
#
# Companion to 2026-11-13-flake-parts-options-migration-design.md.
# This file is documentation. It is `.nix` so your editor highlights it, but it
# lives under docs/ and is never imported — `modules/` is the import root, and
# import-tree would otherwise pick it up.
#
# Say you want to run Miniflux on oserv at miniflux.ogama.me. In the old tree
# that was four edits in four files plus remembering two of them. Here it is
# one file plus one line.
#
# Where it goes: modules/features/server/miniflux.nix
#
# What changes outside this file: one line in modules/hosts/oserv/_toggles.nix.
#   ogama.server.miniflux.enable = true;
# That is all. No imports list, nowhere.

# ---------------------------------------------------------------------------
# The outer function is a FLAKE-PARTS module. Its arguments are flake-level:
# `self`, `inputs`, `lib`, `config` (the flake config). It does not receive
# `pkgs` — there is no system at this level.
#
# Its only job is to register a named module. It does not configure anything.
{ ... }:

let
  # -------------------------------------------------------------------------
  # Options that must exist on BOTH sides.
  #
  # The NixOS and Home Manager evaluations are separate module systems. A host
  # sets its flags in one shared modules/hosts/<host>/_toggles.nix, imported by
  # both, so any flag it sets has to be DECLARED by both — otherwise the side
  # that never declared it errors with "option does not exist".
  #
  # So: declare the enable once here, register it to both sides below, and put
  # the implementation only on the side that implements it. That is why
  # _toggles.nix carries enable flags and nothing else.
  sharedOptions = { lib, ... }: {
    options.ogama.server.miniflux.enable =
      lib.mkEnableOption "Miniflux RSS reader, behind caddy";
  };
in
{
  # `flake.featureModules.nixos.<name>` is the attribute the aggregator in
  # modules/_flake/aggregate.nix collects. Everything registered there is
  # imported into BOTH NixOS hosts, unconditionally. That is the point: the
  # module is always evaluated, so it cannot rot, and `enable` is what decides
  # whether it does anything.
  #
  # Pick <name> to match the file. If a concern has a Home Manager half too,
  # register `flake.featureModules.home.<name>` in this same file right below.
  flake.featureModules.nixos.miniflux =

    # ---------------------------------------------------------------------
    # The inner function is an ordinary NIXOS module. Normal arguments:
    # `config` is the host's full NixOS config, `pkgs` / `upkgs` / `lpkgs`
    # come from _module.args set in modules/_flake/pkg-sets.nix.
    { config, lib, pkgs, ... }:

    let
      # Read shared data off `config`, not off a `cfg` attrset passed through
      # specialArgs. `cfg` no longer exists.
      inherit (config.ogama) identity server;

      # Local shorthand for this module's own option branch. Conventional in
      # nixpkgs modules and keeps the mkIf body readable.
      cfg = config.ogama.server.miniflux;

      host = "miniflux";
      port = 8085;
    in
    {
      # -------------------------------------------------------------------
      # 1. DECLARE THE SWITCH
      #
      # One `enable` per feature. `mkEnableOption` gives you a bool defaulting
      # to false with a sensible description.
      #
      # Defaulting to false is right for a server service: it runs on exactly
      # one host. Desktop pieces are the opposite — they default to
      # `config.ogama.desktop.enable` so that turning on a compositor brings
      # the whole rig, e.g.
      #
      #   options.ogama.desktop.laserbar.enable = lib.mkOption {
      #     type = lib.types.bool;
      #     default = config.ogama.desktop.sway.enable;  # sway-bound: sway only
      #     description = "The sway laser bar.";
      #   };
      #
      # The enable flag comes from sharedOptions, declared on both sides.
      imports = [ sharedOptions ];

      # Options beyond `enable` are declared on the side that uses them, and
      # are therefore set in that side's entry module rather than in
      # _toggles.nix. Add one whenever a host would otherwise want to edit the
      # module body — a port, a quota, a retention window.
      options.ogama.server.miniflux = {
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = host;
          description = ''
            Subdomain Miniflux is served on, under
            `ogama.server.domain`. Also the name its `*.tail` CNAME must
            use — those records are managed outside this repo and will not
            appear by setting this.
          '';
        };
      };

      # -------------------------------------------------------------------
      # 2. GATE EVERYTHING
      #
      # The whole body goes inside one `mkIf cfg.enable`. With the flag off
      # this module still evaluates — every reference below is type-checked
      # and every path resolved — but contributes nothing to the system.
      #
      # That is the property the old layout did not have, and the reason
      # hyprland and headscale could rot.
      config = lib.mkIf cfg.enable {

        # Secrets. sops files are per-host and stay where they are.
        sops.secrets."miniflux_admin_password".sopsFile = ../../../sops/oserv.yaml;
        sops.templates."miniflux.env".content = ''
          ADMIN_PASSWORD=${config.sops.placeholder.miniflux_admin_password}
        '';

        services.miniflux = {
          enable = true;
          adminCredentialsFile = config.sops.templates."miniflux.env".path;
          config = {
            LISTEN_ADDR = "127.0.0.1:${toString port}";
            BASE_URL = "https://${cfg.subdomain}.${server.domain}";
          };
        };

        # Storage. Paths come from the derived tree, which comes from the
        # three root options (ogama.server.paths.{ssd,hdd,backup}). Never
        # hardcode /mnt/hdd-tmp.
        systemd.tmpfiles.rules = [
          "d ${server.path.hdd.app.miniflux} 0750 miniflux miniflux -"
        ];

        # -----------------------------------------------------------------
        # 3. REGISTER WITH THE SHARED SURFACES — IN THIS FILE
        #
        # This is the part the old layout got wrong. A new service had to be
        # added to modules/nixosconf/status-page.nix (gatus) and
        # host/serveur/nixosconf/grafana.nix (process-exporter) by hand, and
        # forgetting either was invisible.
        #
        # NixOS merges list- and attrset-valued options across every module
        # that sets them. So the service declares its own monitoring, here,
        # next to the thing being monitored. Delete this file and its gatus
        # endpoint and its process matcher go with it.

        services.caddy.virtualHosts."https://${cfg.subdomain}.${server.ipv6Host}".extraConfig = ''
          reverse_proxy http://127.0.0.1:${toString port}
        '';

        # Contributes one endpoint to the list status-page.nix declares.
        ogama.server.statusPage.endpoints = [{
          name = "Miniflux";
          group = "Services";
          url = "http://127.0.0.1:${toString port}/healthcheck";
          conditions = [ "[STATUS] == 200" ];
        }];

        # Contributes one matcher to process-exporter.
        #
        # `comm` is /proc/<pid>/comm: truncated to 15 characters and often a
        # nix wrapper name, so an anchored matcher that looks obviously
        # correct can silently match nothing. Check the real value on the
        # box before trusting it:
        #   systemctl show -p MainPID miniflux.service
        #   cat /proc/<pid>/comm
        ogama.server.processExporter.matchers = [{
          name = "miniflux";
          comm = [ "miniflux" ];
        }];
      };
    };

  # The Home Manager side. Miniflux needs nothing in the user environment, so
  # this registers the declaration and no implementation — which is still
  # required, so that _toggles.nix can set the flag.
  flake.featureModules.home.miniflux = sharedOptions;

  # If it DID need something in your user environment — a client, a shell
  # alias, a theme file — the other half goes here, in this same file, gated on
  # the same option. One concern, one file, both sides:
  #
  # flake.featureModules.home.miniflux = { config, lib, pkgs, ... }: {
  #   imports = [ sharedOptions ];
  #   config = lib.mkIf config.ogama.server.miniflux.enable {
  #     home.packages = [ pkgs.newsflash ];
  #   };
  # };
}

# ---------------------------------------------------------------------------
# Checklist for a new service
#
#   1. modules/features/server/<name>.nix, registering
#      flake.featureModules.nixos.<name>.
#   2. A `sharedOptions` binding declaring `.enable`, registered to BOTH
#      featureModules.nixos.<name> and featureModules.home.<name>. Any further
#      option is declared on the side that uses it.
#   3. Whole body under `lib.mkIf cfg.enable`.
#   4. Read identity/domain/paths from `config.ogama.*`.
#   5. Declare your own caddy vhost, gatus endpoint and process matcher in
#      this file.
#   6. One line in modules/hosts/oserv/_toggles.nix.
#   7. `git add` the new file BY NAME. Flakes only see tracked files, so an
#      unadded module is simply absent and the check passes without it.
#      Never `git add -A` in this repo.
#   8. nix eval --raw .#nixosConfigurations.oserv.config.system.build.toplevel.drvPath
#   9. The *.tail CNAME is an individual record managed outside this repo.
#      Nothing here creates it.
