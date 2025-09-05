{ pkgs, cfg, ... }: {
  imports = [
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/helix.nix
    ../../modules/home-manager/sh.nix
    ../../modules/home-manager/display/font.nix
    ../../modules/home-manager/display/i3.nix
    ../../modules/home-manager/kitty.nix

  ];
  # General informations
  home.username = "${cfg.login}";
  home.homeDirectory = "/home/${cfg.login}";
  home.stateVersion = "25.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
