{ config, pkgs, ... }:

let mod = "SUPER";
in {
  imports = [
    ./animation.nix
    ./hyprpolkitagent.nix
    # ../tofi.nix
    ./waybar.nix
    ./cursor.nix
    ./swaync.nix
    # ./hypridle.nix
    ./hyprsunset.nix
    ./walker.nix
  ];
  home.packages = with pkgs; [
    grim
    slurp
    wlroots
    # swaybg
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    settings = {
      # env = [
      #   "LIBVA_DRIVER_NAME,nvidia"
      #   "__GLX_VENDOR_LIBRARY_NAME,nvidia"
      #   "ELECTRON_OZONE_PLATFORM_HINT,auto"
      # ];

      "$mod" = mod;
      "$animSpeedFast" = 3;

      general = {
        allow_tearing = true;

        border_size = 1;

        monitor = [
          "eDP-1, 1920x1080@120, 0x0, 1" # Laptop screen
          "HDMI-A-1,preferred,auto,1" # Home-cinema
        ];

        snap = {
          enabled = true;
          window_gap = 10;
        };

      };
      decoration = {

        rounding = 5;
        active_opacity = 0.9;
        inactive_opacity = 0.8;
        fullscreen_opacity = 1.0;
        blur = {
          enabled = true;
          size = 5;
        };

      };

      input.touchpad = { disable_while_typing = false; };

      misc = {
        disable_hyprland_logo = true;
        vfr = false;
      };

      # binds = { workspace_back_and_forth = true; };

      cursor.inactive_timeout = 5;

      binds.drag_threshold = 10;
      bind = [ # Bind one click
        # --- système ---
        ",XF86PowerOff,exec,:" # Empêche l'écran de s'éteindre

        "${mod}, Return, exec, alacritty"
        "${mod} SHIFT, Q, killactive"
        "${mod} SHIFT, Return, exec, zen"
        "${mod} SHIFT, R, exec, hyprctl reload"

        "${mod}, H, movefocus, l"
        "${mod}, L, movefocus, r"
        "${mod}, K, movefocus, u"
        "${mod}, J, movefocus, d"

        # --- Lock ---
        "${mod}, Escape, exec, sleep 0.3 && swaylock -C ~/.config/swaylock/config"
        "${mod} SHIFT, Escape, exec, sleep 0.3 && swaylock -C ~/.config/swaylock/config"

        # --- Applications ---
        "${mod} SHIFT, Z, exec, makoctl dismiss"
        "${mod} SHIFT, Space, exec, nautilus"
        "${mod} SHIFT, S, exec, spotify"
        "${mod} SHIFT, B, exec, blueman-manager"
        "${mod} SHIFT, A, exec, pavucontrol"
        "${mod}, P, exec, wl-color-picker"

        # --- Audiomedia ---
        ", XF86AudioPrev, exec, playerctl previous"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPlay, exec, playerctl play-pause"

        # --- Screenshot ---
        '', Print, exec, grim -g "$(slurp)" - | wl-copy''

        "${mod}, Space, togglefloating"
        "${mod}, F, fullscreen, toggle"

      ] ++ (builtins.concatLists (builtins.genList (i:
        let ws = i + 1;
        in [
          "$mod, code:1${toString i}, workspace, ${toString ws}"
          "$mod SHIFT, code:1${toString i}, movetoworkspacesilent, ${
            toString ws
          }"
        ]) 9));

      binde = [
        # --- Son ---

        ''
          , XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ && makoctl dismiss -a && notify-desktop "Volume Level" "$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf \"Volume: %.0f%%\", $2*100;}')"''

        ''
          , XF86AudioLowerVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%- && makoctl dismiss -a && notify-desktop "Volume Level" "$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf \"Volume: %.0f%%\", $2*100;}')"''

        ''
          , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && makoctl dismiss -a && notify-desktop "$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo Sound OFF || echo Sound ON)"''

        # --- Luminosité ---
        ''
          , XF86MonBrightnessUp, exec, brightnessctl --exponent=2 s +10% && makoctl dismiss -a && notify-desktop "Brightness Level" "$(brightnessctl get | awk -v max=$(brightnessctl max) '{printf \"Brightness: %.0f%%\", ($1/max)*100;}')"''

        ''
          , XF86MonBrightnessDown, exec, brightnessctl --exponent=2 s 10%- && makoctl dismiss -a && notify-desktop "Brightness Level" "$(brightnessctl get | awk -v max=$(brightnessctl max) '{printf \"Brightness: %.0f%%\", ($1/max)*100;}')"''

      ];
      bindo = [

        "${mod} SHIFT, O, exec, reboot"
        "${mod} SHIFT, P, exec, shutdown -h now"
      ];
      bindm = [
        "ALT , mouse:272, movewindow"
        "${mod} SHIFT, mouse:272, resizewindow 1"
        "${mod}, mouse:272, resizewindow 2"
      ];
      bindc = [
        "${mod}, mouse:272, togglefloating"
        "ALT, mouse:272, togglefloating"
      ];
    };
  };
}
