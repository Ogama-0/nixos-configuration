{ pkgs, lib, config, ... }:
{
  home.packages = with pkgs; [ dconf ];

  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = lib.mkForce (
          if config.stylix.polarity == "dark" then "prefer-dark"
          else if config.stylix.polarity == "light" then "prefer-light"
          else "default"
        );
      };
    };
  };

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
