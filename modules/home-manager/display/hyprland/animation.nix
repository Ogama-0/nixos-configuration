{ ... }: {
  # Reuse from https://github.com/saatvik333/hyprland-dotfiles/blob/main/hypr/config/animations.conf

  wayland.windowManager.hyprland = {
    settings = {
      animations = {
        enabled = true;

        # Curves
        bezier = [
          "linear, 0, 0, 1, 1"
          "easeIn, 0.42, 0.0, 1, 1"
          "easeOut, 0.0, 0.0, 0.58, 1"
          "balanced, 0.2, 0, 0.3, 1"
          "smooth, 0.25, 0.1, 0.25, 1"
          "crisp, 0.3, 0, 0.4, 1"
          "flow, 0.15, 0, 0.35, 1"
        ];

        # Window animations
        animation = [
          "windows, 1, 4, smooth"
          "windowsIn, 1, 3, balanced, popin"
          "windowsOut, 1, 2, crisp, popin"
          "windowsMove, 1, 3, flow"

          # Fade
          "fadeLayers, 1, 2, smooth"

          # Layers (menus, notifs…)
          "layers, 1, 2, balanced"
          "layersIn, 1, 2, smooth, slide"
          "layersOut, 1, 1, crisp, slide"

          # Borders
          "border, 1, 4, smooth"

          # Workspaces
          "workspaces, 1, 2, easeOut, slide"

          # Special workspace
          "specialWorkspaceIn, 1, $animSpeedFast, easeIn, fade"
          "specialWorkspaceOut, 1, $animSpeedFast, easeOut, fade"
        ];
      };
    };
  };
}
