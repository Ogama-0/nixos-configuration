{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { config, lib, ... }:
    {
      options.ogama.desktop.gtklock.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.ogama.desktop.sway.enable;
        defaultText = lib.literalExpression "config.ogama.desktop.sway.enable";
        description = "the gtklock lock screen and its PAM rules";
      };
    };
in
{
  flake.featureModules.nixos.gtklock =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.desktop.gtklock.enable (
        {
          programs.gtklock = {
            enable = true;

            config = {
              main = {
                idle-hide = true;
                idle-timeout = 10;

                modules = [
                  "${pkgs.gtklock-userinfo-module}/lib/gtklock/userinfo-module.so"
                  "${pkgs.gtklock-playerctl-module}/lib/gtklock/playerctl-module.so"
                  "${pkgs.gtklock-powerbar-module}/lib/gtklock/powerbar-module.so"
                ];
              };
              playerctl = {
                art-size = 64;
                position = "top-center";
              };
            };

            modules = with pkgs; [
              gtklock-userinfo-module
              gtklock-playerctl-module
              gtklock-powerbar-module
            ];

            style = builtins.readFile ./style.css;
          };

          environment.etc."xdg/gtklock/layout.xml".source = ./layout.xml;
        }
      );
    };

  flake.featureModules.home.gtklock = sharedOptions;
}
