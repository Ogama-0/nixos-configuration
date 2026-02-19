{ cfg, pkgs, ... }: {
  imports = [
    ./home-manager/tool.nix
    ../../modules/home-manager/sh.nix
    ../../modules/home-manager/alacritty.nix
    ../../modules/home-manager/display/sway
    # ../../modules/home-manager/display/hyprland
    ../../modules/home-manager/helix.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/display/font.nix
    ../../modules/home-manager/zed-editor.nix
    ../../modules/home-manager/display/gtk.nix
    ../../modules/home-manager/joplin-desktop.nix
    ../../modules/home-manager/zellij
    ../../modules/home-manager/firefox.nix
    ../../modules/home-manager/stylix.nix
    # "${inputs.home-manager}/modules/programs/xcompose.nix"
    # ./vm-compose.nix
  ];

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };
  home = {

    pointerCursor = {
      gtk.enable = true;
      package = pkgs.vanilla-dmz;
      name = "Vanilla-DMZ";
    };

    username = "ogama";
    homeDirectory = "/home/ogama";
    sessionVariables.swp = "${cfg.share.swapsev_path}";

    stateVersion = "24.11";
  };

  services.poweralertd.enable = true;

  programs.home-manager.enable = true;
}
