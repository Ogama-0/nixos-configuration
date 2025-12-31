{ ... }: {
  wayland.windowManager.hyprland.settings = {
    bind = [ "$mod, D, exec, walker" "$mod SHIFT, D, exec, walker" ];
  };

  services.walker = {
    enable = true;

    settings = {

      app_launch_prefix = "";
      as_window = false;
      close_when_open = true;
      disable_click_to_close = false;
      force_keyboard_focus = false;
      hotreload_theme = false;
      locale = "";
      monitor = "";
      terminal_title_flag = "";
      theme = "default";
      timeout = 0;
    };
  };
}
