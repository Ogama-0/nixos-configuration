{ config, pkgs, ... }:

{

  imports = [
    ./sh.nix
    ./display/windowsManager.nix
    ./helix.nix
    ./tools.nix
    ./git.nix
    ./display/font.nix
    ./display/mako.nix
    ./zed-editor.nix
    ./display/gtk.nix
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

    # Main pkgs
    firefox
    vesktop
    spotify
    gimp
    bitwarden-desktop
    # google-chrome
    unityhub
    nautilus
    jetbrains-toolbox

    # game
    modrinth-app
    steam
    steam-run
    # Dev
    jetbrains.rider
    git
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
  services.poweralertd.enable = true;

  programs.home-manager.enable = true;
}
