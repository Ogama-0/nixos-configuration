{ pkgs, config, ... }:
let
  colors = import ../../lib/theme-colors.nix;

  colorDefs = c: ''
    @define-color base00 #${c.base00};
    @define-color base02 #${c.base02};
    @define-color base03 #${c.base03};
    @define-color base05 #${c.base05};
    @define-color base07 #${c.base07};
    @define-color base08 #${c.base08};
    @define-color base09 #${c.base09};
    @define-color base0B #${c.base0B};
    @define-color base0C #${c.base0C};
    @define-color base0D #${c.base0D};
    @define-color base0E #${c.base0E};
  '';
in
{
  xdg.configFile = {
    "waybar/colors-dark.css".text = colorDefs colors.dark;
    "waybar/colors-light.css".text = colorDefs colors.light;
  };

  home.activation.waybarColorDefault = pkgs.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/waybar/colors-dark.css" "${config.xdg.configHome}/waybar/colors.css"
  '';

  programs.waybar = {
    enable = true;

    settings = {
      mainBar = {
        height = 30;
        position = "bottom";
        spacing = 5;

        modules-left = [ "hyprland/workspaces" "custom/media" ];

        modules-center = [ "hyprland/window" ];
        modules-right = [
          "mpd"
          "pulseaudio"
          "network"
          "power-profiles-daemon"
          "backlight"
          "battery"
          "battery#bat2"
          "clock"
          "tray"
        ];

        keyboard-state = {
          numlock = true;
          capslock = true;
          format = "{name} {icon}";
          format-icons = {
            locked = "";
            unlocked = "";
          };
        };

        "sway/mode" = { format = ''<span style="italic">{}</span>''; };

        "sway/scratchpad" = {
          format = "{icon} {count}";
          show-empty = false;
          format-icons = [ "" "" ];
          tooltip = true;
          tooltip-format = "{app}: {title}";
        };

        mpd = {
          format =
            "{stateIcon} {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}{artist} - {album} - {title} ({elapsedTime:%M:%S}/{totalTime:%M:%S}) ⸨{songPosition}|{queueLength}⸩ {volume}% ";
          format-disconnected = "Disconnected ";
          format-stopped =
            "{consumeIcon}{randomIcon}{repeatIcon}{singleIcon}Stopped ";
          unknown-tag = "N/A";
          interval = 5;

          consume-icons.on = " ";
          random-icons = {
            off = ''<span color="#e93c58"></span> '';
            on = " ";
          };
          repeat-icons.on = " ";
          single-icons.on = " ";
          state-icons = {
            paused = "";
            playing = "";
          };
        };

        tray = { spacing = 10; };

        clock = {
          tooltip-format = ''
            <big>{:%Y %B}</big>
            <tt><small>{calendar}</small></tt>'';
          format-alt = "{:%Y-%m-%d}";
        };

        backlight = {
          format = "{percent}% {icon}";
          format-icons = [ "" "" "" "" "" "" "" "" "" ];
          on-click = "swaync-client -t";
        };

        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{capacity}% {icon}";
          format-full = "{capacity}% {icon}";
          format-charging = "{capacity}% ";
          format-plugged = "{capacity}% ";
          format-alt = "{time} {icon}";
          format-icons = [ "" "" "" "" "" ];
        };

        "battery#bat2" = { bat = "BAT2"; };

        power-profiles-daemon = {
          format = "{icon}";
          tooltip = true;
          tooltip-format = ''
            Power profile: {profile}
            Driver: {driver}'';
          format-icons = {
            default = "";
            performance = "";
            balanced = "";
            power-saver = "";
          };
        };

        network = {
          format-wifi = "{essid} ({signalStrength}%) ";
          format-ethernet = "{ipaddr}/{cidr} ";
          tooltip-format = "{ifname} via {gwaddr} ";
          format-linked = "{ifname} (No IP) ";
          format-disconnected = "Disconnected ⚠";
          format-alt = "{ifname}: {ipaddr}/{cidr}";
        };

        pulseaudio = {
          format = "{volume} % {icon} {format_source}";
          format-bluetooth = "{volume} % {icon}  {format_source}";
          format-bluetooth-muted = "🔇 {icon} {format_source}";
          format-muted = "🔇 {format_source}";
          format-source = "{volume}% ";
          format-source-muted = "";
          format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = [ "" "" "" ];
          };
          on-click = "pavucontrol";
        };
      };
    };

    style = ''
      @import url("colors.css");

      window#waybar {
        background-color: @base00;
        color: @base05;
      }

      #clock,
      #battery,
      #network,
      #pulseaudio,
      #tray,
      #power-profiles-daemon,
      #backlight,
      #mpd {
        padding: 0 10px;
        color: @base05;
      }

      #workspaces button {
        padding: 0 5px;
        background-color: transparent;
        color: @base05;
      }

      #workspaces button.focused,
      #workspaces button.active {
        background-color: @base02;
        box-shadow: inset 0 -3px @base0D;
      }

      #battery.charging,
      #battery.plugged {
        color: @base00;
        background-color: @base0B;
      }

      #battery.critical:not(.charging) {
        background-color: @base08;
        color: @base00;
      }

      #network.disconnected {
        background-color: @base08;
      }
    '';
  };

  wayland.windowManager.hyprland.settings.exec-once = [ "waybar" ];
}
