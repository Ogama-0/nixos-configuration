{ pkgs, ... }:
{
  home.packages = with pkgs; [ dconf ];

  # color-scheme is deliberately not set here: darkman owns that key and
  # rewrites it on every sunrise/sunset (see modules/home-manager/darkman.nix).
  # Setting it statically made each activation stomp the current mode.
  dconf.enable = true;

  gtk = {
    enable = true;
    # theme = {

    #   name = "orchis-theme";
    #   package = pkgs.orchis-theme;
    # };
    # iconTheme = {
    #   name = "Adwaita";
    #   package = pkgs.adwaita-icon-theme;
    # };
    # cursorTheme = {
    #   name = "Adwaita";
    #   package = pkgs.adwaita-icon-theme;
    # };
  };
}
