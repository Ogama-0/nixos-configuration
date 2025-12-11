{ inputs, lib, pkgs, cfg, ... }:
let
  inherit (inputs) stylix;
  background_monocle = ../../assets/background/background_monocle.png;

in {

  # imports = [ stylix.homeModules.stylix ];
  stylix = {
    enable = true;

    targets.alacritty.enable = false;
    targets.swaylock.enable = false;
    targets.fish.enable = false;
    targets.mako.enable = false;
    targets.starship.enable = false;

    base16Scheme =
      lib.mkDefault "${pkgs.base16-schemes}/share/themes/horizon-dark.yaml";
    image = background_monocle;
    polarity = "dark";
    fonts = {
      sansSerif = {
        package = pkgs.inter;
        name = "Inter";
      };
      serif = {
        package = pkgs.merriweather;
        name = "Merriweather";
      };
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };

      sizes = {
        applications = 12;
        terminal = 10;

        desktop = 12;
        popups = 14;
      };
    };
    # cursor = //TODO
    # icons = //TODO
  };
}
