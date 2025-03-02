{ pkgs, ... }:

{
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

      ring-color = "17191e";
      key-hl-color = "880033";
      line-color = "00000000";
      inside-color = "00000088";
      separator-color = "00000000";
    };
  };
}
