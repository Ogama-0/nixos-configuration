{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.dev.zed.enable = lib.mkEnableOption "the zed editor";
    };
in
{
  flake.featureModules.nixos.zed = sharedOptions;

  flake.featureModules.home.zed =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.dev.zed.enable (
        {
          programs.zed-editor = {
            enable = true;

            extensions =
              [ "nix" "html" "python" "dockerfile" "horizon" "latex" "C#" "wakatime" ];

            userSettings = {
              "auto_install_extensions" = {
                "html" = true;
                "dockerfile" = true;
                "docker-compose" = true;
                "python" = true;
                "horizon" = true;
                "LaTeX" = true;
                "c" = true;
                "c#" = true;
                "nix" = true;
                "wakatime" = true;

              };

              "base_keymap" = "JetBrains";

              # "theme" = {
              #   "mode" = "system";
              #   "light" = "Horizon";
              #   "dark" = "Horizon";
              # };

            };
          };
        }
      );
    };
}
