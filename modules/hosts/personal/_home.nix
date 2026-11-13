{ cfg, pkgs, ... }:
{
  imports = [
    ./home-manager/tool.nix
    ./home-manager/default-app.nix
    ../../home-manager/sh.nix
    ../../home-manager/alacritty.nix
    ../../home-manager/display/sway
    # ../../home-manager/display/hyprland
    ../../home-manager/helix.nix
    ../../home-manager/git.nix
    ../../home-manager/display/font.nix
    ../../home-manager/zed-editor.nix
    ../../home-manager/display/gtk.nix
    # ../../home-manager/joplin-desktop.nix
    ../../home-manager/zellij
    ../../home-manager/firefox.nix
    ../../home-manager/darkman.nix
    ../../home-manager/vim.nix
    ../../home-manager/keyboard.nix
    ../../home-manager/wakapi.nix
    ../../home-manager/calendar-sync.nix
    ../../home-manager/thunderbird.nix
    ../../home-manager/nix-gc.nix
    ../../home-manager/gns3.nix
    # "${inputs.home-manager}/modules/programs/xcompose.nix"
  ];

  sops.age.keyFile = "${cfg.home_path}/.config/sops/age/keys.txt";

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
