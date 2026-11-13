# Part of the hyprland feature, which imports this unconditionally —
# imports instruct the module system and cannot be conditional — so the
# gate lives here.
{ lib, config, pkgs, ... }:
{
  config = lib.mkIf config.ogama.desktop.hyprland.enable (
    {
      home.pointerCursor = {
        name = "capitaine-cursors";
        package = pkgs.capitaine-cursors;
        size = 24;
      };

      home.sessionVariables = {
        XCURSOR_THEME = "capitaine-cursors";
        XCURSOR_SIZE = "24";
        HYPRCURSOR_THEME = "capitaine-cursors";
        HYPRCURSOR_SIZE = "24";
      };
      wayland.windowManager.hyprland.settings.env =
        [ "HYPRCURSOR_THEME,capitaine-cursors" "HYPRCURSOR_SIZE,24" ];

    }
  );
}
