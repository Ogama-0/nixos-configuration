{ pkgs, upkgs, ... }:

let
  # swayidle runs commands via `sh -c` with a PATH containing only bash, so
  # every binary here must be referenced by its full store path.
  swaylock = "${pkgs.swaylock-effects}/bin/swaylock";
  quickshell = "${upkgs.quickshell}/bin/quickshell";
  pidof = "${pkgs.procps}/bin/pidof";
  pkill = "${pkgs.procps}/bin/pkill";

  # Same lock command as the "${modifier}+Escape" keybinding in ./default.nix.
  lockWithSwaylock = "${pidof} swaylock || ${swaylock} -C ~/.config/swaylock/config";

  # Drop swaylock (if up) and hand off to the quickshell lockscreen.
  lockWithQuickshell = "${pkill} -x swaylock; ${quickshell} ipc -c widgets call lock lock";
in
{
  services.swayidle = {
    enable = true;

    timeouts = [
      {
        timeout = 60; # 1min idle: quick lock, same as the manual shortcut.
        command = lockWithSwaylock;
      }
      {
        timeout = 300; # 5min idle: escalate to the quickshell lockscreen.
        command = lockWithQuickshell;
      }
    ];

    events = {
      # Closing the lid ("clap") suspends the machine; lock with
      # quickshell before that happens.
      before-sleep = lockWithQuickshell;
    };
  };
}
