{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.desktop.font.enable = lib.mkEnableOption "desktop fonts";
    };
in
{
  flake.featureModules.nixos.font = sharedOptions;

  flake.featureModules.home.font =
    { lib, config, pkgs, lpkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.desktop.font.enable (
        {
          home.packages = with pkgs; [
            noto-fonts
            noto-fonts-color-emoji
            nerd-fonts.jetbrains-mono
            nerd-fonts.ubuntu-mono
            nerd-fonts.caskaydia-cove
            font-awesome
            merriweather
            inter
            # monocraft
            lpkgs.corpta-font
            lpkgs.orbitron-font
          ];

          fonts.fontconfig = {
            enable = true;
            defaultFonts = {
              serif = [ "Noto Sans" "Merriweather" ];
              sansSerif = [ "Inter" ];
              # monospace = [ "monocraft" ];
              monospace = [ "JetBrainsMonoNerdFont-Regular" ];
              emoji = [ "Noto Color Emoji" ];
            };
          };
        }
      );
    };
}
