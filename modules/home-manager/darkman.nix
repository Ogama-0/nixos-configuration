{ pkgs, lib, config, ... }:
let
  dconfExe = "${pkgs.dconf}/bin/dconf";
in
{
  services.darkman = {
    enable = true;
    package = pkgs.darkman;

    settings = {
      # Defaults to Paris; Task 2 overrides this from /etc/timezone at
      # every home-manager activation.
      lat = 48.8566;
      lng = 2.3522;
      usegeoclue = false;
    };

    darkModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
      '';
    };

    lightModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
      '';
    };
  };
}
