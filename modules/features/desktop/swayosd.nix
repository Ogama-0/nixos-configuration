{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { config, lib, ... }:
    {
      options.ogama.desktop.swayosd.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.ogama.desktop.sway.enable;
        defaultText = lib.literalExpression "config.ogama.desktop.sway.enable";
        description = "the volume/brightness/mute on-screen display";
      };
    };
in
{
  flake.featureModules.nixos.swayosd = sharedOptions;

  flake.featureModules.home.swayosd =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      imports = [ sharedOptions ];

      # SwayOSD draws the volume, mic and brightness readouts that used to be
      # notifications.
      #
      # They were sent as TRANSIENT notifications so the laser bar's toast
      # surface would show them and the centre would not keep them - which
      # worked, but meant a volume keypress went through a DBus server, a
      # record, a group, a pack and a layer surface built for things you might
      # want to act on. SwayOSD is the surface that readings actually want:
      # one pill, no history, no actions, and it does the wpctl/brightnessctl
      # call itself, so the keybinding is one command rather than a script
      # that parses `wpctl get-volume` output.
      #
      # The sway keybindings call `swayosd-client` directly and send no
      # notification at all - see modules/features/desktop/sway/default.nix.
      # Having both would mean two things on screen for one keypress.
      config = lib.mkIf config.ogama.desktop.swayosd.enable (
        let
          stylePath = "${config.xdg.configHome}/swayosd/style.css";
          styles = import ../../../lib/swayosd-style.nix { inherit pkgs; };
        in
        {
          services.swayosd = {
            enable = true;

            # style.css is rewritten at runtime by darkman and so must NOT be
            # managed by xdg.configFile - a managed path is a read-only store
            # symlink darkman cannot replace. Seeded by the activation script
            # below, exactly as alacritty's colors.toml is.
            stylePath = stylePath;

            # Low centre. The notification toasts own the top right and the
            # laser bar owns the very bottom edge; a readout that lands on
            # either is competing with something it has nothing to do with.
            topMargin = 0.78;
          };

          # Seeded only when missing. Seeding unconditionally would hand a
          # daytime desktop the dark stylesheet on every switch, until
          # darkman's next run corrected it.
          home.activation.swayosdStyleDefault = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            run ${pkgs.coreutils}/bin/mkdir -p "${config.xdg.configHome}/swayosd"
            if [ ! -e "${stylePath}" ]; then
              run ${pkgs.coreutils}/bin/install -m 644 ${styles.dark} "${stylePath}"
            fi
          '';
        }
      );
    };
}
