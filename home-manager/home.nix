{ config, pkgs, ... }:

{

  imports = [
    ./sh.nix
    ./windowsManager.nix
    ./helix.nix
    ./tools.nix
    ./git.nix
    ./font.nix
  ];

  home.username = "ogama";
  home.homeDirectory = "/home/ogama";

  home.stateVersion = "24.11"; # Please read the comment before changing.

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };

  home.packages = with pkgs; [

    jetbrains-toolbox
    jetbrains.rider

    hello
    octaveFull
  ];

  programs.bash = {

    enable = true;
    shellAliases = {
      ll = "ls -l";
      ".." = "cd ..";
      cdnix = "cd /home/ogama/documents/github/nixos-configuration";
    };
  };

  programs.home-manager.enable = true;
}
