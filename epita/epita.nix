{ pkgs, cfg, ... }: {
  imports = [
    ../modules/home-manager/git.nix
    ../modules/home-manager/helix.nix
    ../modules/home-manager/sh.nix
    ../modules/home-manager/display/fonts.nix
    .../modules/home-manager/display/i3.nix
    ../modules/home-manager/joplin-desktop.nix
  ];
  # General informations
  home.username = "${cfg.login}";
  home.homeDirectory = "/home/${cfg.login}";
  home.stateVersion = "25.05";

  # Packages
  home.packages = with pkgs; [ spotify ];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
