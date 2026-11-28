{ config, pkgs, ... }:
{
  imports = [
    ./_toggles.nix
  ];
  home = {

    username = "ogama";
    homeDirectory = "/home/ogama";
    sessionVariables.swp = "${config.ogama.share.swapsevPath}";

    stateVersion = "24.11";
  };
  programs.home-manager.enable = true;
}
