{ pkgs, config, lib, ... }:
let
  script_path = ../../../../scripts/swaync;
  colors = import ../../../lib/theme-colors.nix;

  colorDefs = c: ''
    @define-color base00 #${c.base00};
    @define-color base02 #${c.base02};
    @define-color base05 #${c.base05};
    @define-color base08 #${c.base08};
    @define-color base0D #${c.base0D};
  '';

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

  xdg.configFile = {
    "swaync/colors-dark.css".text = colorDefs colors.dark;
    "swaync/colors-light.css".text = colorDefs colors.light;
  };

  home.activation.swayncColorDefault = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/swaync/colors-dark.css" "${config.xdg.configHome}/swaync/colors.css"
  '';

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
    };
    style = ''
      @import url("colors.css");

      :root {
        --border-radius: 22px;
        --cc-bg: @base00;
        --widget-background: @base02;
        --padding: calc(var(--border-radius) / 2);
      }

      .notification-group {
        background: @base00;
        color: @base05;
        border-radius: var(--border-radius);
        padding: 8px;
      }

      .notification-background.critical {
        background: @base08;
      }

      .widgets > .widget {
        background: var(--widget-background);
        color: @base05;
        padding: calc(var(--border-radius) / 2);
      }
    '';
  };
}
