{ inputs, lib, pkgs, config, cfg, ... }:
let
  inherit (inputs) stylix;
  background_monocle = ../../assets/background/background_monocle.png;

in {

  # imports = [ stylix.homeModules.stylix ];
  stylix = {
    enable = true;
    autoEnable = true;

    targets.alacritty.enable = false;
    targets.swaylock.enable = false;
    targets.fish.enable = false;
    # targets.mako.enable = true;
    targets.starship.enable = false;
    targets.tofi.enable = true;
    # targets.swaync.enable = false;
    targets.waybar = {
      enable = true;
      # enableLeftBackColors = true;
      # enableRightBackColors = true;
      # enableCenterBackColors = true;
      opacity.enable = false;
      # colors.override = config.lib.stylix.colors;
    };

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
      emoji = {
        package = pkgs.noto-fonts-monochrome-emoji;
        name = "Noto Emoji";
      };

      sizes = {
        applications = 13;
        terminal = 10;

        desktop = 12;
        popups = 14;
      };
    };
    opacity = {
      applications = 0.9;
      desktop = 0.5;
      popups = 0.9;
      terminal = 0.95;
    };
    # cursor = //TODO
    icons = {
      enable = true;
      dark = "candy-icons";
      light = "candy-icons";
      package = pkgs.candy-icons;

    };
  };
}
