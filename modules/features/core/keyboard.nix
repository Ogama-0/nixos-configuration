{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.core.keyboard.enable = lib.mkEnableOption "keyboard layout and key repeat";
    };
in
{
  flake.featureModules.nixos.keyboard = sharedOptions;

  flake.featureModules.home.keyboard =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.core.keyboard.enable (
        {
          # home.keyboard = {
          #   layout = "fr";
          #   options = [ "caps:escape" ];
          # };

          wayland.windowManager.sway = {
            config = {
              input = {
                "type:keyboard" = {
                  xkb_options = "caps:escape";
                  xkb_layout = "us";
                  # xkb_layout = "fr";
                };
              };
            };
          };

        }
      );
    };
}
