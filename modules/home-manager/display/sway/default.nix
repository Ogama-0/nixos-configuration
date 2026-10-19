{
  config,
  lib,
  pkgs,
  ...
}:

let
  modifier = "Mod4";
  up = "k";
  down = "j";
  left = "h";
  right = "l";
in
{
  imports = [
    # ./barbar.nix
    ./effects.nix
    ./quickshell
    ../../gammastep.nix
    ./idle.nix
    ../vicinae.nix
    ../swaylockTrollKristentenervepascestjustelideeesttropbien.nix
  ];
  home.packages = with pkgs; [
    grim
    slurp
    wlroots
  ];
  # swaylock-effect
  services.autotiling.enable = true;
  wayland.windowManager.sway = {
    enable = true;
    xwayland = true;
    # SwayFX: sway plus rounded corners / shadows / blur, configured in
    # ./effects.nix. Defined in modules/lib/swayfx.nix because greetd execs
    # the very same binary to start the session.
    package = import ../../../lib/swayfx.nix pkgs;
    # Sway initialises a renderer even for `--validate` (swaywm/sway#4691),
    # and swayfx's fx_renderer is GLES2-only: in the Nix sandbox it dies on
    # "Cannot create GLES2 renderer: no DRM FD available" before it ever
    # reads the config. Plain sway passed only because wlr_renderer falls
    # back to pixman. Validate by hand instead:
    #   swayfx --validate --config ~/.config/sway/config
    checkConfig = false;
    config = {
      modifier = "${modifier}";
      terminal = "alacritty";

      up = "${up}";
      down = "${down}";
      left = "${left}";
      right = "${right}";
      defaultWorkspace = "workspace 10";

      # No swaybar from the typed option - home-manager would otherwise ship
      # its default one. The bar block in extraConfig below is not a bar: it
      # exists only to make sway track the modifier for us.
      bars = [ ];

      startup = [
        { command = "alacritty"; }
        {
          command = "systemctl --user restart quickshell-widgets";
          always = true;
        }
      ];

      fonts = {
        names = [ "Noto Sans" ];
        size = 12.0;
      };

      window = {
        titlebar = false;
        border = 0;

        commands = [
          # The file picker the panel opens for "Send file". zenity hands
          # the job to the XDG portal, so the window to catch is the
          # portal's and not zenity's - matching app_id="zenity" catches
          # nothing at all.
          #
          # Tiled it took the whole screen for a dialog whose job is to
          # pick one path.
          {
            criteria.app_id = "xdg-desktop-portal-gtk";
            command = "floating enable, resize set 760 480, move position center";
          }

          # Everything KDE Connect puts on screen: the app, the handler and
          # the transfer window. The whole family, because which of them
          # appears depends on what you asked for, and they all want the
          # same treatment - small, out of the way, top left.
          {
            criteria.app_id = "^org\\.kde\\.kdeconnect";
            command = "floating enable, resize set 480 320, move position 24 24";
          }
        ];
      };

      # A sway mode that exists for exactly one key.
      #
      # The panel must not hold keyboard focus - you are meant to carry on
      # typing into whatever is underneath it - but Escape still has to
      # dismiss it, and a layer surface cannot receive a key it does not
      # have focus for. A mode is the only mechanism in sway that intercepts
      # ONE key and lets every other one through to the focused window.
      #
      # Every normal binding is copied in, so nothing stops working while
      # the panel is up. ControlPanel.qml enters this mode when the panel
      # opens and returns to default when it closes, by any route - so a
      # click outside or a workspace change leaves the mode too.
      modes.panel = config.wayland.windowManager.sway.config.keybindings // {
        "Escape" = "mode default; exec quickshell ipc -c widgets call panel dismiss";
      };

      keybindings = lib.mkOptionDefault {
        "${modifier}+Shift+Return" = "exec zen-beta";
        "${modifier}+Shift+o" = "exec reboot";
        "${modifier}+Shift+p" = "exec shutdown -h now";
        "${modifier}+Shift+r" = "exec swaymsg reload";
        "${modifier}+${left}" = "focus left";
        "${modifier}+${right}" = "focus right";
        "${modifier}+${up}" = "focus up";
        "${modifier}+${down}" = "focus down";
        "${modifier}+Escape" = "exec quickshell ipc -c widgets call lock lock";
        "${modifier}+Shift+Escape" = "exec sleep 0.3 && swaylock -C ~/.config/swaylock/config";
        # Was: "${modifier}" = "exec swaymsg bar mode toggle";
        # Commented out because the laser bar now binds the same key (see
        # extraConfig). Two bindings on the bare modifier compete, and the
        # second one is the likely reason sway stopped firing the --release
        # that collapses the bar. Restore it if you still want the swaybar
        # toggle and would rather move the laser bar to another key.
        "${modifier}+Shift+z" = "exec quickshell ipc -c widgets call panel clearNotifications";
        # "${modifier}+Shift+d" = "exec vesktop";
        "${modifier}+space" = "exec nautilus";
        "${modifier}+Shift+s" = "exec spotify";
        "${modifier}+Shift+b" = "exec blueman-manager";
        "${modifier}+Shift+a" = "exec pavucontrol";
        "${modifier}+p" = "exec wl-color-picker";
        "${modifier}+w" = "exec quickshell ipc -c widgets call wallpaper togglePicker";
        # Hold mod (which raises the bar), then n. A normal binding works
        # here where a bare-modifier one would not: sway only stops firing
        # the --release of the modifier ITSELF once it has been used as one.
        "${modifier}+n" = "exec quickshell ipc -c widgets call panel toggle";

        # Workspace related keys
        "${modifier}+grave" = "workspace 10";
        "${modifier}+1" = "workspace 1";
        "${modifier}+2" = "workspace 2";
        "${modifier}+3" = "workspace 3";
        "${modifier}+4" = "workspace 4";
        "${modifier}+5" = "workspace 5";
        "${modifier}+6" = "workspace 6";
        "${modifier}+7" = "workspace 7";
        "${modifier}+8" = "workspace 8";
        "${modifier}+9" = "workspace 9";
        "${modifier}+0" = "workspace 10";

        "${modifier}+Shift+grave" = "move container to workspace 10";
        "${modifier}+Shift+1" = "move container to workspace 1";
        "${modifier}+Shift+2" = "move container to workspace 2";
        "${modifier}+Shift+3" = "move container to workspace 3";
        "${modifier}+Shift+4" = "move container to workspace 4";
        "${modifier}+Shift+5" = "move container to workspace 5";
        "${modifier}+Shift+6" = "move container to workspace 6";
        "${modifier}+Shift+7" = "move container to workspace 7";
        "${modifier}+Shift+8" = "move container to workspace 8";
        "${modifier}+Shift+9" = "move container to workspace 9";
        "${modifier}+Shift+0" = "move container to workspace 10";

        "${modifier}+r" = "mode resize";

        # Control keys

        "XF86AudioPrev" = "exec playerctl previous";
        "XF86AudioNext" = "exec playerctl next";
        "XF86AudioPlay" = "exec playerctl play-pause";

        "XF86AudioRaiseVolume" =
          ''exec wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+'';

        "XF86AudioLowerVolume" =
          ''exec wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%-'';
        "XF86AudioMute" =
          "exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";

        "XF86MonBrightnessUp" =
          ''exec brightnessctl --exponent=2 s +10%'';
        "XF86MonBrightnessDown" =
          ''exec brightnessctl --exponent=2 s 10%-'';

        "Print" = ''exec grim -g "$(slurp)" - | wl-copy'';
      };
    };

    extraConfig = ''
      # Not a bar. swaybar_command is a no-op, so no bar process ever starts
      # and nothing is drawn.
      #
      # It exists because `mode hide` + `modifier` is the only thing in sway
      # that gives an exact correspondence between the modifier being held and
      # a bar being shown: sway tracks the key in the compositor and
      # broadcasts the result as the bar_state_update IPC event. Key bindings
      # cannot do this - sway stops firing a modifier's --release binding once
      # it has been used as a modifier, so mod+key leaves the hide unsent.
      #
      # The modifier is the only way in: no key binding reveals the bar. If
      # the subscription ever dies LaserBar.qml relaunches it with backoff,
      # which is what makes a fallback binding unnecessary.
      #
      # LaserBar.qml subscribes to bar_state_update and follows
      # visible_by_modifier.
      bar {
          swaybar_command ${pkgs.coreutils}/bin/true
          mode hide
          hidden_state hide
          modifier ${modifier}
      }
    '';
  };
}
