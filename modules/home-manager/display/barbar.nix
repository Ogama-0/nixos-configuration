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
            separator = "<span size='18000'></span>";
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
              echo '{ "text": "' "$mode"'", "state": "Info" }'
            else
              echo '{ "text": "' "$mode"'" }'
            fi
          '';
          json = true;
          interval = "once";
          click = [{
            button = "left";
            cmd = "makoctl mode -t 'dnd'";
            update = true;
          }];
        }
        { block = "sound"; }
        {
          block = "music";
        }
        # {
        #   block = "calendar";
        #   next_event_format = " $icon $start.datetime(f:'%a %H:%M') $summary ";
        #   ongoing_event_format =
        #     " $icon $summary (ends at $end.datetime(f:'%H:%M')) ";
        #   no_events_format = " $icon no events ";
        #   fetch_interval = 30;
        #   alternate_events_interval = 10;
        #   events_within_hours = 48;
        #   warning_threshold = 600;
        #   browser_cmd = "firefox";
        #   source = [{
        #     url =
        #       "http://p154-caldav.icloud.com/published/2/MTc0MzczOTgwODExNzQzNxPr8IrQhOG8X1scqqU1h6QhoW6RWcyU2leiHN00JJIhjylt6njWzrrgKOzy3AIPgIWLSzBtQkVG5Jm7SJ7cqeU/";
        #     auth = { type = "unauthenticated"; };
        #   }
        #   # { url = ""; }
        #     ];
        # }
        { # Vpn
          block = "custom";
          shell = "fish";
          command = ''
            tailscale status | grep -q "Tailscale is stopped" ; and echo "Vpn Down" ; or echo "Vpn Up"
          '';

          interval = 5;
          # json = true;
          click = [{
            button = "left";
            cmd = ''
              tailscale status | grep -q "Tailscale is stopped" ; and tailscale up ; or tailscale down'';
            update = true;
          }];
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
        { # ping
          block = "custom";
          json = true;
          command = ''
            echo "{\"icon\":\"ping\",\"text\":\"`ping -c4 1.1.1.1 | tail -n1 | cut -d'/' -f5`\"}"'';
          interval = 60;
          click = [{
            button = "left";
            cmd = "<command>";
          }];
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
  wayland.windowManager.sway.config.bars = [{
    statusCommand =
      "${pkgs.i3status-rust}/bin/i3status-rs /home/ogama/.config/i3status-rust/config-default.toml";
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
  }];
}
