# Part of the hyprland feature, which imports this unconditionally —
# imports instruct the module system and cannot be conditional — so the
# gate lives here.
{ lib, config, ... }:
{
  config = lib.mkIf config.ogama.desktop.hyprland.enable (
    {
      services.hyprsunset = {
        enable = true;
        settings = {
          profile = [
            {
              time = "7:30";
              identity = true;
            }
            {
              time = "21:00";
              temperature = 5000;
              gamma = 0.8;
            }
          ];
        };
      };
      wayland.windowManager.hyprland.settings.exec-once = [ "hyprsunset" ];
    }
  );
}
