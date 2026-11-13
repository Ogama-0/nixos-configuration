# Part of the hyprland feature, which imports this unconditionally —
# imports instruct the module system and cannot be conditional — so the
# gate lives here.
{ lib, config, ... }:
{
  config = lib.mkIf config.ogama.desktop.hyprland.enable (
    {
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
  );
}
