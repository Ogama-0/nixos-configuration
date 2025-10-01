{ ... }: {
  imports = [
    ./perso-mod/tool.nix
    ../../modules/home-manager/sh.nix
    ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/display/windowsManager.nix
    ../../modules/home-manager/helix.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/display/font.nix
    ../../modules/home-manager/display/mako.nix
    ../../modules/home-manager/zed-editor.nix
    ../../modules/home-manager/display/gtk.nix
    ../../modules/home-manager/joplin-desktop.nix
    ../../modules/home-manager/zellij/default.nix
    # "${inputs.home-manager}/modules/programs/xcompose.nix"
    # ./vm-compose.nix
  ];

  home.username = "ogama";
  home.homeDirectory = "/home/ogama";

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };

  home.stateVersion = "24.11"; # Please read the comment before changing.

  services.poweralertd.enable = true;

  programs.home-manager.enable = true;
}
