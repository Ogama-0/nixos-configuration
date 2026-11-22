{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.immich.enable = lib.mkEnableOption "the Immich photo server";
    };
in
{
  flake.featureModules.nixos.immich =
    {
      lib,
      upkgs,
      config,
      ...
    }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.server.immich.enable (
        let
          # Two names for the same backend: ipv6Host's AAAA points straight at
          # oserv, so Caddy can win ACME for it directly; publicHost is the
          # bare public name (AAAA now also direct, A still VPS-fronted). Both
          # vhosts force the Host header to publicHost so Immich's
          # externalDomain always matches, same as opencloud.nix.
          publicHost = "immich.${config.ogama.server.domain}";
          ipv6Host = "immich.${config.ogama.server.ipv6Host}";
          immichRoot = "${config.ogama.server.path.hdd.app.immich}";

          proxy = ''
            reverse_proxy http://[::1]:${toString config.services.immich.port} {
              header_up Host "${publicHost}"
              transport http {
                read_timeout  600s
                write_timeout 600s
              }
            }
          '';
        in
        {
          # systemd.tmpfiles.rules = [
          #   "d ${immichRoot}                0755 immich immich -"
          #   "d ${immichRoot}/upload         0755 immich immich -"
          #   "d ${immichRoot}/encoded-video  0755 immich immich -"
          #   "d ${immichRoot}/thumbs         0755 immich immich -"
          #   "d ${immichRoot}/library        0755 immich immich -"
          #   "d ${immichRoot}/profile        0755 immich immich -"
          #   "d ${immichRoot}/backups        0755 immich immich -"
          # ];
          # environment.sessionVariables.IMMICH_IGNORE_MOUNT_CHECK_ERRORS = "true";

          services.immich = {
            package = upkgs.immich;
            enable = true;
            port = 2283;

            mediaLocation = "${immichRoot}";

            database = {
              enable = true;
              createDB = true;
            };
            machine-learning.enable = true;

            redis = {
              enable = true;
              port = 2281;
            };
            settings.server = {
              externalDomain = "https://${publicHost}";
              newVersionCheck.enabled = true;
            };
          };

          services.caddy.virtualHosts."https://${ipv6Host}" = {
            extraConfig = proxy;
          };
          services.caddy.virtualHosts."https://${publicHost}" = {
            extraConfig = proxy;
          };

          # caddy.nix's "http://*.${domain}" catch-all claims port 80 for
          # every subdomain, so Caddy won't add this redirect on its own.
          services.caddy.virtualHosts."http://${ipv6Host}" = {
            extraConfig = ''
              redir https://{host}{uri} permanent
            '';
          };
        }
      );
    };

  flake.featureModules.home.immich = sharedOptions;
}
