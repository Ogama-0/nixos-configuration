{ pkgs, ... }:
{
  # adw-gtk3 and papirus-icon-theme are NOT installed here. This module is
  # imported by `epita` too, which has no darkman and so would carry hundreds
  # of megabytes of themes nothing selects. They live in darkman.nix instead,
  # beside the scripts that actually choose between their variants.
  #
  # They are also deliberately NOT declared via gtk.theme / gtk.iconTheme:
  # home-manager's gtk module writes both gtk-3.0/settings.ini and the dconf
  # keys, so every activation would stomp whatever mode darkman last selected.
  # darkman owns all three keys (color-scheme, gtk-theme, icon-theme).
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
