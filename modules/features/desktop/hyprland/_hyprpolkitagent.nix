# Part of the hyprland feature, which imports this unconditionally —
# imports instruct the module system and cannot be conditional — so the
# gate lives here.
{ lib, config, ... }:
{
  config = lib.mkIf config.ogama.desktop.hyprland.enable (
    {
      services.hyprpolkitagent.enable = true;

      wayland.windowManager.hyprland.settings.exec-once =
        [ "systemctl --user start hyprpolkitagent" ];

    }
  );
}
