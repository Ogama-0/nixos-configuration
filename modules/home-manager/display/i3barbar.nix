{ pkgs, cfg, ... }:

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
            separator = "<span size='14500'></span>";
            idle_bg = "#17191e";
          };
        };
      };
      blocks = [
        { block = "sound"; }
        { block = "music"; }
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
          block = "time";
          interval = 60;
          format = " $icon $timestamp.datetime(f:'%a %d/%m %R') ";
        }
      ];
    };
  };

  xsession.windowManager.i3.config.bars = [{
    statusCommand =
      "${pkgs.i3status-rust}/bin/i3status-rs ${cfg.home_path}/.config/i3status-rust/config-default.toml";
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
