{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.desktop.kitty.enable = lib.mkEnableOption "the kitty terminal";
    };
in
{
  flake.featureModules.nixos.kitty = sharedOptions;

  flake.featureModules.home.kitty =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.desktop.kitty.enable (
        {
          programs.kitty = {
            enable = true;

            settings = {
              confirm_os_window_close = 0;
              enable_audio_bell = "no";
              macos_option_as_alt = "left";
            };

            shellIntegration = {
              mode = "enabled";
              enableFishIntegration = true;
            };

            font = {
              # name = "UbuntuMonoNerdFontMono";
              name = "JetBrainsMonoNerdFont-Regular";
              # name = "CaskaydiaCoveNerdFont";
              size = 13;
            };

            extraConfig = ''
              disable_ligatures never
              shell fish
            '';
          };
        }
      );
    };
}
