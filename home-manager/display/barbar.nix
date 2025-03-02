{ pkgs, ... }:

{
  programs.i3status-rust = {
    enable = true;
    bars.default = {
      icons = "awesome6";
      theme = "modern";

      settings = {
        theme = {
          theme = "modern";
          overrides = {
            separator = "<span size='18000'></span>";
            idle_bg = "#17191e";
          };
        };
      };

      blocks = [
        # {
        #   block = "custom";
        #     command = "echo  $(${lib.getExe' pkgs.mako "makoctl"} mode)";
        #     click = [
        #       {
        #         button = "left";
        #         cmd = "${lib.getExe' pkgs.mako "makoctl"} mode -t dnd";
        #         update = true;
        #       }
        #     ];
        #     interval = "once";
        #   }
        {
          block = "custom";
          shell = "fish";
          command =
            "systemctl status wg-quick-oscar.service | grep 'Active' | grep 'exited' | string match -qr '\\S' && echo 'VPN On' || echo 'VPN Off' ";
          interval = 5;
          click = [{
            button = "left";
            cmd = "zenity --password | sudo -S echo bonjour ; togglewg";
            update = true;
          }];
        }
        # {
        #   block = "custom";
        #   shell = "fish";
        #   command = "echo (kijesui)";
        #   interval = "once";
        # }
        {
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
        { block = "music"; }
        { block = "sound"; }
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
          info_type = "available";
          interval = 60;
          warning = 20.0;
          alert = 10.0;
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
