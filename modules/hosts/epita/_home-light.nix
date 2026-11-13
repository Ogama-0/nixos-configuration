{ pkgs, cfg, ... }: {
  imports = [
    ../../home-manager/git.nix
    ../../home-manager/helix.nix
    ../../home-manager/sh.nix
    ../../home-manager/display/font.nix
    ../../home-manager/display/i3
    ../../home-manager/kitty.nix
    ../../home-manager/wakapi.nix
    ../../home-manager/nh.nix
  ];

  sops.age.keyFile = "/home/${cfg.login}/.config/sops/age/keys.txt";

  # General informations
  home.username = "${cfg.login}";
  home.homeDirectory = "/home/${cfg.login}";
  home.stateVersion = "25.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
