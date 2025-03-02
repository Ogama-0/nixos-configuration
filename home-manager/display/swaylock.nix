{ pkgs, ... }:
let
  background = toString ../assets/background.png;
  background_blure = toString ../assets/background_blure.png;
  background_tache = toString ../assets/background_tache.png;
  background_monocle = toString ../assets/babackground_monocle;
in {
  programs.swaylock = {
    enable = true;
    package = pkgs.swaylock-effects;

    settings = {
      daemonize = true;
      ignore-empty-password = true;
      show-failed-attempts = true;
      screenshots = true;
      clock = true;
      font = "Noto Sans";

      indicator = false;
      indicator-radius = 100;
      indicator-thickness = 7;
      hide-keyboard-layout = true;
      indicator-x-position = 150;
      indicator-y-position = 930;

      effect-blur = "7x5";
      effect-vignette = "0.5:0.5";

      ring-color = "17191e";
      key-hl-color = "880033";
      line-color = "00000000";
      inside-color = "00000088";
      separator-color = "00000000";
    };
  };
}

