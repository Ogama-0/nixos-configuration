{ inputs, config, pkgs, ... }: {
  imports = [
    ./perso-mod/tool.nix
    ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/display/windowsManager.nix
    ../../modules/home-manager/helix.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/display/font.nix
    ../../modules/home-manager/display/mako.nix
    ../../modules/home-manager/zed-editor.nix
    ../../modules/home-manager/display/gtk.nix
    ../../modules/home-manager/joplin-desktop.nix
    # "${inputs.home-manager}/modules/programs/xcompose.nix"
    # ./vm-compose.nix
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
