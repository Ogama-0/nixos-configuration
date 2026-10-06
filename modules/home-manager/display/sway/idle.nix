{ pkgs, upkgs, ... }:

let
  # swayidle runs commands via `sh -c` with a PATH containing only bash, so
  # every binary here must be referenced by its full store path.
  swaylock = "${pkgs.swaylock-effects}/bin/swaylock";
  quickshell = "${upkgs.quickshell}/bin/quickshell";
  pidof = "${pkgs.procps}/bin/pidof";
  pkill = "${pkgs.procps}/bin/pkill";
  swaymsg = "${pkgs.sway}/bin/swaymsg";
  playerctl = "${pkgs.playerctl}/bin/playerctl";

  # Same lock command as the "${modifier}+Escape" keybinding in ./default.nix.
  lockWithSwaylock = "${pidof} swaylock || ${swaylock} -C ~/.config/swaylock/config";

  # Drop swaylock (if up) and hand off to the quickshell lockscreen.
  lockWithQuickshell = "${pkill} -x swaylock; ${quickshell} ipc -c widgets call lock lock";

  # Browsers only request the Wayland idle-inhibit protocol for fullscreen
  # video, so a normal windowed tab playing video doesn't stop swayidle.
  # Browsers (and most media players) expose an MPRIS player while playing,
  # so skip the timeout command whenever playerctl reports one as "Playing".
  skipIfPlaying = cmd: "${playerctl} -a status 2>/dev/null | grep -q Playing || (${cmd})";
in
{
  services.swayidle = {
    enable = true;

    timeouts = [
      {
        timeout = 180; # 3min idle: quick lock, same as the manual shortcut.
        command = skipIfPlaying lockWithSwaylock;
      }
      {
        timeout = 300; # 5min idle: escalate to the quickshell lockscreen.
        command = skipIfPlaying lockWithQuickshell;
      }
      {
        timeout = 600; # 10min idle: turn off the screens.
        command = skipIfPlaying "${swaymsg} \"output * power off\"";
        resumeCommand = "${swaymsg} \"output * power on\"";
      }
    ];

    events = {
      # Closing the lid ("clap") suspends the machine; lock with
      # quickshell before that happens.
      before-sleep = lockWithQuickshell;
    };
  };
}
