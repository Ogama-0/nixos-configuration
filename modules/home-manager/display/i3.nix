{ pkgs, lib, ... }:

let
  modifier = "Mod4";
  terminal = "alacritty";
  up = "k";
  down = "j";
  left = "h";
  right = "l";
in {
  home.packages = with pkgs; [ playerctl maim xclip i3lock-fancy-rapid feh ];

  xsession.enable = true;

  xsession.windowManager.i3 = {
    enable = true;
    config = {
      modifier = modifier;
      terminal = terminal;

      keybindings = lib.mkOptionDefault {
        # Basic keys
        "${modifier}+Return" = "exec ${terminal}";
        "${modifier}+Shift+q" = "kill";
        "${modifier}+Shift+Return" = "exec firefox";
        # "${modifier}+Shift+r" = "exec reboot";
        # "${modifier}+Shift+p" = "exec shutdown -h now";
        "${modifier}+Escape" = "exec sleep 0.3 && i3lock-fancy-rapid 0 1";
        "${modifier}+Shift+s" = "exec spotify";
        "${modifier}+Shift+e" = "exit";
        "${modifier}+Shift+f" = "exec nautilus";

        # Movements
        "${modifier}+${left}" = "focus left";
        "${modifier}+${right}" = "focus right";
        "${modifier}+${up}" = "focus up";
        "${modifier}+${down}" = "focus down";

        # Workspaces
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

        # Resize mode
        "${modifier}+r" = "mode resize";

        # Media
        "XF86AudioPrev" = "exec playerctl previous";
        "XF86AudioNext" = "exec playerctl next";
        "XF86AudioPlay" = "exec playerctl play-pause";

        # Screenshot with maim
        "Print" =
          "exec --no-startup-id bash -c 'maim -s | xclip -selection clipboard -t image/png'";
      };

      modes = {
        resize = {
          "${left}" = "resize shrink width 10 px";
          "${right}" = "resize grow width 10 px";
          "${up}" = "resize shrink height 10 px";
          "${down}" = "resize grow height 10 px";
          "Escape" = "mode default";
        };
      };

      startup = [{
        command =
          "feh --bg-fill ${../../../assets/background/background_monocle.png}";
        always = true;
      }];

      fonts = {
        names = [ "Noto Sans" ];
        size = 12.0;
      };

      window = {
        titlebar = false;
        border = 0;
      };
    };
  };
}
