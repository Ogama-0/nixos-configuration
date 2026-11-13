{ config, ... }: {
  imports = [
    ./_toggles.nix
    # global import
    ../../home-manager/sh.nix
    ../../home-manager/helix.nix
    ../../home-manager/git.nix
    ../../home-manager/display/font.nix
    ../../home-manager/wakapi.nix
    ./_home-manager/tools.nix
  ];

  # Per-host identity, formerly host/profiles.nix's cfg-server.
  ogama.identity = {
    user = "ogama_serv";
    mail = "oscar.cornut@gmail.com";
    sshPubkey = "AAAAC3NzaC1lZDI1NTE5AAAAIHBd3Ol/Z20sasLURoDV4pHsXZ4yqmbacAYv1Uv+iyG6";
  };

  sops.age.keyFile = "${config.ogama.identity.homePath}/.config/sops/age/keys.txt";

  home = {

    username = config.ogama.identity.user;
    homeDirectory = config.ogama.identity.homePath;
    sessionVariables = {
      swp = "${config.ogama.server.path.ssd.share.swapsev_path}";
    };

    stateVersion = "24.11";
  };
  # Please read the comment before changing.
  programs.home-manager.enable = true;
}
