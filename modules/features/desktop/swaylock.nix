{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { config, lib, ... }:
    {
      options.ogama.desktop.swaylock.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.ogama.desktop.sway.enable;
        defaultText = lib.literalExpression "config.ogama.desktop.sway.enable";
        description = "the lock screen";
      };
    };
in
{
  flake.featureModules.nixos.swaylock = sharedOptions;

  flake.featureModules.home.swaylock =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.desktop.swaylock.enable (
        {
          programs.swaylock = {
            enable = true;
            package = pkgs.swaylock-effects;

            settings = {
              daemonize = true;
              ignore-empty-password = true;
              show-failed-attempts = true;
              screenshots = true;
              clock = true;
              font = "Noto Sans";

              indicator = false;
              indicator-radius = 100;
              indicator-thickness = 7;
              hide-keyboard-layout = true;
              indicator-x-position = 150;
              indicator-y-position = 930;

              ring-color = "17191e";
              key-hl-color = "880033";
              line-color = "00000000";
              inside-color = "00000088";
              separator-color = "00000000";
            };
          };
        }
      );
    };
}
