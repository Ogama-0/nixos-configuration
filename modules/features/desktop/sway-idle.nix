{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { config, lib, ... }:
    {
      options.ogama.desktop.swayIdle = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = config.ogama.desktop.sway.enable;
          defaultText = lib.literalExpression "config.ogama.desktop.sway.enable";
          description = "idle timeouts, screen blanking and suspend";
        };

        # Read by two modules that cannot see each other's internals: this one
        # builds the `[ -e ... ]` guard in front of every timeout command, and
        # the laser bar substitutes it into the control panel's idle tile as
        # @idleInhibitFlag@ (see laserbar/default.nix). Declaring it as an
        # option is what keeps those two from drifting - a hardcoded name in
        # both places reads fine and silently stops working the day one side
        # is renamed, because an absent flag file is indistinguishable from
        # "idle management is on".
        #
        # The basename only. $XDG_RUNTIME_DIR cannot be interpolated here:
        # swayidle's guard runs through `sh -c` and expands it, but the panel
        # builds its Process argv without a shell and has to read the variable
        # itself. One name, two ways of resolving the directory.
        inhibitFlagName = lib.mkOption {
          type = lib.types.str;
          default = "laserbar-idle-inhibit";
          description = "basename under $XDG_RUNTIME_DIR whose presence suspends the idle timeouts";
        };
      };
    };
in
{
  flake.featureModules.nixos.swayIdle = sharedOptions;

  flake.featureModules.home.swayIdle =
    {
      lib,
      config,
      pkgs,
      upkgs,
      ...
    }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.desktop.swayIdle.enable (
        let
          # swayidle runs commands via `sh -c` with a PATH containing only bash, so
          # every binary here must be referenced by its full store path.
          quickshell = "${upkgs.quickshell}/bin/quickshell";
          swaymsg = "${pkgs.sway}/bin/swaymsg";
          playerctl = "${pkgs.playerctl}/bin/playerctl";

          inhibitFlag = "\"$XDG_RUNTIME_DIR/${config.ogama.desktop.swayIdle.inhibitFlagName}\"";

          # Hand off to the quickshell lockscreen - the same lock the
          # "${modifier}+Escape" keybinding in ./default.nix calls.
          #
          # This used to `pkill -x swaylock` first, because an earlier design
          # locked with swaylock at 3min and escalated to quickshell at 5min.
          # Two lock clients in sequence is the one shape to avoid here: both
          # speak ext-session-lock-v1, and killing the first while it holds the
          # lock is precisely how sway ends up with an abandoned lock and
          # paints the red screen that only a reboot clears. One lock client,
          # one stage. swaylock is still bound to Mod+Shift+Escape by hand.
          lockWithQuickshell = "${quickshell} ipc -c widgets call lock lock";

          # Browsers only request the Wayland idle-inhibit protocol for fullscreen
          # video, so a normal windowed tab playing video doesn't stop swayidle.
          # Browsers (and most media players) expose an MPRIS player while playing,
          # so skip the timeout command whenever playerctl reports one as "Playing".
          skipIfPlaying = cmd: "${playerctl} -a status 2>/dev/null | grep -q Playing || (${cmd})";

          # The control panel's idle tile, which is just this file's presence.
          # A flag file rather than `systemctl --user stop swayidle`, because
          # stopping the service would take `before-sleep` with it and the lid
          # would start suspending to an unlocked session. Closing the lid must
          # lock whatever the tile says; the tile governs the *idle* timeouts
          # and nothing else.
          skipIfInhibited = cmd: "[ -e ${inhibitFlag} ] || (${cmd})";

          # Order matters only for readability - both guards are pure tests.
          guard = cmd: skipIfInhibited (skipIfPlaying cmd);
        in
        {
          services.swayidle = {
            enable = true;

            timeouts = [
              {
                timeout = 300; # 5min idle: the lockscreen.
                command = guard lockWithQuickshell;
              }
              {
                timeout = 600; # 10min idle: turn the screens off.
                command = guard "${swaymsg} \"output * power off\"";
                # Deliberately unguarded: whatever stopped the blank from
                # happening, the screens still have to come back when the
                # machine is touched. A guarded resume that loses its race
                # leaves a laptop with a black panel and no way to tell it is
                # awake.
                resumeCommand = "${swaymsg} \"output * power on\"";
              }
            ];

            events = {
              # Closing the lid ("clap") suspends the machine; lock with
              # quickshell before that happens. NOT guarded by the panel tile:
              # see skipIfInhibited above.
              before-sleep = lockWithQuickshell;
            };
          };
        }
      );
    };
}
