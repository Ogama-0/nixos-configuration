{ pkgs, ... }:
let
  script_path = ../../../../scripts/swaync;
  wifi = {
    command = script_path + "/wifi-toggle.sh";
    update-command = script_path + "/update-wifi-toggle.sh";
  };
  bluetooth = {
    command = script_path + "/bluetooth-toggle.sh";
    update-command = script_path + "/update-bluetooth-toggle.sh";
  };
  power = {
    command = script_path + "/power-toggle.sh";
    update-command = script_path + "/update-power-toggle.sh";
  };
  night-shift = {
    command = script_path + "/night-shift-toggle.sh";
    update-command = script_path + "/update-night-shift-toggle.sh";
  };
in {

  services.swaync = {
    enable = true;
    settings = {

      positionX = "right";
      positionY = "bottom";

      control-center-positionX = "none";
      control-center-positionY = "none";
      control-center-margin-top = 8;
      control-center-margin-bottom = 8;
      control-center-margin-right = 8;
      control-center-margin-left = 8;
      control-center-width = 500;
      control-center-height = 700;

      fit-to-screen = false;
      layer-shell-cover-screen = true;

      layer-shell = true;
      layer = "overlay";
      control-center-layer = "overlay";
      cssPriority = "user";

      notification-body-image-height = 100;
      notification-body-image-width = 200;
      notification-inline-replies = false;

      timeout = 5;
      timeout-low = 3;
      timeout-critical = 0;
      notification-window-width = 500;
      keyboard-shortcuts = true;
      image-visibility = "always";
      transition-time = 200;
      hide-on-clear = true;
      hide-on-action = true;
      script-fail-notify = true;

      widgets = [ "inhibitors" "dnd" "mpris" "buttons-grid" "notifications" ];

      widget-config = {
        buttons-grid = {
          buttons-per-row = 4;
          actions = [
            ({
              label = "󰤨";
              type = "toggle";
              active = true;
            } // wifi)

            ({
              label = "󰂯";
              active = true;
              type = "toggle";
            } // bluetooth)

            ({
              label = "󰾅";
              type = "button";
            } // power)
            ({
              label = "🔅";
              active = true;
              type = "button";
            } // night-shift)

          ];

        };
      };
      # style = ''
      #           :root {
      #     --border-radius: 22px;
      #     --cc-bg: transparent;

      #     --widget-background: rgba(46, 46, 46, 0.7);
      #     --noti-bg-alpha: 0.6;

      #     --padding: calc(var(--border-radius) / 2);
      #   }

      #   .control-center {
      #     border-radius: 0;

      #     border-radius: var(--border-radius);
      #   }

      #   .widgets > .widget,
      #   .widget-mpris > carouselindicatordots,
      #   .widget-mpris > box > button {
      #     background: var(--widget-background);
      #     padding: calc(var(--border-radius) / 2);
      #     border: var(--border);
      #   }

      #   .control-center-list-placeholder {
      #     padding: var(--border-radius);
      #   }

      #   .notification-group {
      #     border-radius: var(--border-radius);
      #     padding: 8px;
      #   }

      #   .widget.widget-mpris {
      #     background: transparent;
      #     border-radius: 0;
      #     padding: 0;
      #     border: none;
      #   }
      #   .widget.widget-mpris > carouselindicatordots {
      #     --dots-padding: 4px;
      #     padding: var(--dots-padding);
      #     padding-left: var(--dots-padding);
      #     padding-right: calc(6px + var(--dots-padding));
      #     margin: 0;
      #     margin-top: var(--padding);
      #   }
      #   .widget-mpris > box > button:hover {
      #     background: rgba(46, 46, 46, 1);
      #   }
      #   .widget-mpris-player {
      #     box-shadow: none;
      #     border: var(--border);
      #     margin: 0 var(--padding);
      #   }
      #   .widget-mpris-player:only-child {
      #     margin: 0;
      #   }
      # '';

    };
  };
}
