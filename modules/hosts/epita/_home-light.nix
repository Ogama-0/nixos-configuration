{ config, pkgs, ... }: {
  imports = [
    ./_toggles-light.nix
    ../../home-manager/git.nix
    ../../home-manager/helix.nix
    ../../home-manager/sh.nix
    ../../home-manager/display/font.nix
    ../../home-manager/display/i3
    ../../home-manager/kitty.nix
    ../../home-manager/wakapi.nix
    ../../home-manager/nh.nix
  ];

  # Per-host identity, formerly host/profiles.nix's cfg-epita. The school
  # account name and the login happen to be the same string, but they are
  # different things and both were recorded separately before.
  ogama.identity = {
    user = "oscar.cornut";
    login = "oscar.cornut";
    isEpita = true;
  };

  sops.age.keyFile = "/home/${config.ogama.identity.login}/.config/sops/age/keys.txt";

  # General informations
  home.username = "${config.ogama.identity.login}";
  home.homeDirectory = "/home/${config.ogama.identity.login}";
  home.stateVersion = "25.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
