{ cfg, ... }: {
  imports = [
    # global import
    ../../modules/home-manager/sh.nix
    ../../modules/home-manager/helix.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/display/font.nix
  ];

  home.username = cfg.user;
  home.homeDirectory = cfg.home_path;

  home.stateVersion = "24.11"; # Please read the comment before changing.

  programs.bash = {

    enable = true;
    shellAliases = {
      ll = "ls -l";
      ".." = "cd ..";
    };
  };
  services.poweralertd.enable = true;

  programs.home-manager.enable = true;
}
