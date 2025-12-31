{ pkgs, ... }: {
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
