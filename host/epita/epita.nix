{ pkgs, cfg, ... }: {
  imports = [
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/helix.nix
    ../../modules/home-manager/sh.nix
    ../../modules/home-manager/display/font.nix
    ../../modules/home-manager/display/i3
    ../../modules/home-manager/joplin-desktop.nix
    # ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/display/gtk.nix
    ../../modules/home-manager/alacritty.nix
    ../../modules/home-manager/zellij/default.nix
  ];
  # General informations
  home.username = "${cfg.login}";
  home.homeDirectory = "/home/${cfg.login}";
  home.stateVersion = "25.05";

  # Packages
  home.packages = with pkgs; [ spotify nautilus wdisplays pavucontrol ];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
