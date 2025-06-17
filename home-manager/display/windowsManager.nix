{ lib, pkgs, ... }:

let
  modifier = "Mod4";
  up = "k";
  down = "j";
  left = "h";
  right = "l";
  background = toString ../../assets/background.png;
  background_blure = toString ../../assets/background_blure.png;
  background_tache = toString ../../assets/background_tache.png;
  background_monocle = toString ../../assets/babackground_monocle;
in {
  imports = [ ./barbar.nix ./swaylock.nix ./tofi.nix ];
  home.packages = with pkgs; [ grim slurp wlroots swaybg ];

  wayland.windowManager.sway = {
    enable = true;
    xwayland = true;
    wrapperFeatures.gtk = true; # Fixes common issues with GTK 3 apps
    config = {
      modifier = "${modifier}";
      terminal = "kitty";

      up = "${up}";
      down = "${down}";
      left = "${left}";
      right = "${right}";
      defaultWorkspace = "workspace 10";

      startup = [{ command = "kitty"; }];

      fonts = {
        names = [ "Noto Sans" ];
        size = 12.0;
      };

      window = {
        titlebar = false;
        border = 0;
      };

      keybindings = lib.mkOptionDefault {
        "${modifier}+Shift+Return" = "exec firefox";
        "${modifier}+Shift+r" = "exec reboot";
        "${modifier}+Shift+p" = "exec shutdown -h now";
        "${modifier}+${left}" = "focus left";
        "${modifier}+${right}" = "focus right";
        "${modifier}+${up}" = "focus up";
        "${modifier}+${down}" = "focus down";
        "${modifier}+Escape" =
          "exec sleep 0.3 && swaylock -C ~/.config/swaylock/config";
        "${modifier}+Shift+Escape" =
          "exec sleep 0.3 && swaylock -C ~/.config/swaylock/config";
        "${modifier}" = "exec swaymsg bar mode toggle";
        "${modifier}+Shift+z" = "exec makoctl dismiss";
        "${modifier}+Shift+d" = "exec vesktop";
        "${modifier}+space" = "exec nautilus";
        "${modifier}+Shift+s" = "exec spotify";
        "${modifier}+Shift+b" = "exec blueman-manager";
        "${modifier}+Shift+a" = "exec pavucontrol";
        "${modifier}+p" = "exec wl-color-picker";

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

        "XF86AudioRaiseVolume" = ''
          exec wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ && makoctl dismiss -a && notify-desktop "Volume Level" "$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf \"Volume: %.0f%%\", $2*100;}')"'';

        "XF86AudioLowerVolume" = ''
          exec wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%- &&  makoctl dismiss -a && notify-desktop "Volume Level" "$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf \"Volume: %.0f%%\", $2*100;}')"'';
        "XF86AudioMute" =
          "exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && makoctl dismiss -a && notify-desktop $(wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q 'MUTED' && printf 'Sound OFF' || printf 'Sound ON')";

        "XF86MonBrightnessUp" = ''
          exec brightnessctl --exponent=2 s +10% && makoctl dismiss -a && notify-desktop "Brightness Level" "$(brightnessctl get | awk -v max=$(brightnessctl max) '{printf "Brightness: %.0f%%", ($1/max)*100;}')"'';
        "XF86MonBrightnessDown" = ''
          exec brightnessctl --exponent=2 s 10%- && makoctl dismiss -a && notify-desktop "Brightness Level" "$(brightnessctl get | awk -v max=$(brightnessctl max) '{printf "Brightness: %.0f%%", ($1/max)*100;}')"'';

        "Print" = ''exec grim -g "$(slurp)" - | wl-copy'';
      };
    };

    extraConfig = ''
      exec_always swaybg -i ${background_monocle} -m fill
    '';

  };

}
