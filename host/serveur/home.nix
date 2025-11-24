{ cfg, ... }: {
  imports = [
    # global import
    ../../modules/home-manager/sh.nix
    ../../modules/home-manager/helix.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/display/font.nix
  ];
  home = {

    username = cfg.user;
    homeDirectory = cfg.home_path;
    sessionVariables.swp = "${cfg.server.share.swapsev_path}";

    stateVersion = "24.11";
  }; # Please read the comment before changing.
  programs.home-manager.enable = true;
}
