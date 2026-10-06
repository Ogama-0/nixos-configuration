{ pkgs, ... }:

{
  programs.i3status-rust = {
    enable = true;
    bars.default = {
      theme = "modern";
      icons = "awesome6";
      settings = {
        theme = {
          theme = "modern";
          overrides = {
            separator = "<span size='19000'></span>";
            idle_bg = "#17191e";
          };
        };
      };
      blocks = [
        {
          block = "custom";
          command = ''
            mode=$(makoctl mode | tail -n1)
            if [ "$mode" = "dnd" ]; then
              echo "{ \"text\": \"$mode\", \"state\": \"Info\" }"
            else
              echo "{ \"text\": \"$mode\" }"
            fi
          '';
          json = true;
          interval = "once";
          click = [
            {
              button = "left";
              cmd = "makoctl mode -t 'dnd'";
              update = true;
            }
          ];
        }
        {
          # Toggle swayidle (lock/screen-off timers) on/off from the bar.
          block = "custom";
          command = ''
            if systemctl --user -q is-active swayidle; then
              echo "{ \"text\": \"idle on\" }"
            else
              echo "{ \"text\": \"idle off\", \"state\": \"Warning\" }"
            fi
          '';
          json = true;
          interval = "once";
          click = [
            {
              button = "left";
              # i3status-rust/swaybar fires a single click's cmd twice in
              # quick succession, which races the toggle with itself (stop,
              # then start again) and leaves swayidle back on. Debounce by
              # ignoring a second firing within 500ms of the last one.
              cmd = ''
                debounce=/tmp/swayidle-toggle-$USER.debounce
                now=$(date +%s%N)
                last=$(cat "$debounce" 2>/dev/null || echo 0)
                [ $(( (now - last) / 1000000 )) -lt 500 ] && exit 0
                echo "$now" > "$debounce"
                systemctl --user -q is-active swayidle && systemctl --user stop swayidle || systemctl --user start swayidle
              '';
              update = true;
            }
          ];
        }
        { block = "sound"; }
        {
          block = "music";
        }
        {
          # Vpn
          block = "custom";
          shell = "fish";
          command = ''
            tailscale status | grep -q "Tailscale is stopped" ; and echo "Vpn Down" ; or echo "Vpn Up"
          '';

          interval = 5;
          # json = true;
          click = [
            {
              button = "left";
              cmd = ''tailscale status | grep -q "Tailscale is stopped" ; and tailscale up ; or tailscale down'';
              update = true;
            }
          ];
        }
        {
          block = "custom";
          shell = "fish";
          command = ''
            ping -6 -c1 google.com >/dev/null 2>&1; and echo ipv6; or echo no ipv6
          '';
          interval = 60;
          # json = true;

        }
        {
          block = "net";
          format = " $icon  $ssid ($signal_strength) ";
          interval = 60;
        }
        {
          block = "memory";
          icons_format = "";
          format = " $icon $mem_used_percents.eng(w:2) ";
          interval = 10;
        }
        {
          block = "cpu";
          icons_format = "";
          format = " $icon $utilization ";
          interval = 10;
        }
        {
          block = "battery";
          driver = "upower";
          interval = 30;
          warning = 20;
          critical = 10;
          format = " $icon $percentage ";
          empty_format = " $icon $percentage ";
          full_format = " $icon $percentage ";
        }
        {
          block = "disk_space";
          path = "/";
          info_type = "used";
          interval = 60;
          warning = 80.0;
          alert = 90.0;
          format = " $icon $available ";
          format_alt = " $icon  $percentage ";
        }
        {
          block = "time";
          interval = 60;
          format = " $icon $timestamp.datetime(f:'%a %d/%m %R') ";
        }
      ];
    };
  };
  wayland.windowManager.sway.config.bars = [
    {
      statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs /home/ogama/.config/i3status-rust/config-default.toml";
      mode = "hide";
      fonts.size = 11.0;

      colors = {
        background = "#17191e";

        focusedWorkspace = rec {
          text = "#ffffff";
          background = "#61AFEF";
          border = background;
        };

        inactiveWorkspace = rec {
          text = "#abb2bf";
          background = "#282c34";
          border = background;
        };

        urgentWorkspace = rec {
          text = "#ffffff";
          background = "#bf4034";
          border = background;
        };
      };
    }
  ];
}
