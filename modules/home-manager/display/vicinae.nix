{ lib, upkgs, ... }:
let
  colors = import ../../lib/theme-colors.nix;

  # Vicinae derives its ~50 remaining semantic colors (list selection, input
  # borders, tooltips, ...) from these, inheriting whatever is left from the
  # built-in vicinae-dark / vicinae-light themes.
  mkTheme = variant: c: {
    meta = {
      version = 1;
      name = "Horizon ${variant}";
      description = "Horizon ${variant}, from modules/lib/theme-colors.nix";
      inherit variant;
      inherits = "vicinae-${variant}";
    };

    colors = {
      core = {
        background = "#${c.base00}";
        secondary_background = "#${c.base01}";
        border = "#${c.base02}";
        foreground = "#${c.base05}";
        accent = "#${c.base0D}";
      };

      accents = {
        red = "#${c.base08}";
        orange = "#${c.base09}";
        yellow = "#${c.base0A}";
        green = "#${c.base0B}";
        cyan = "#${c.base0C}";
        blue = "#${c.base0D}";
        magenta = "#${c.base0E}";
        purple = "#${c.base0E}";
      };

      # Pinned rather than derived, so the selected row keeps matching the
      # base02 highlight tofi used.
      list.item.selection = {
        background = "#${c.base02}";
        secondary_background = "#${c.base03}";
      };
      grid.item.background = "#${c.base01}";
    };
  };
in
{
  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    "Mod4+d" = "exec vicinae toggle";
  };

  programs.vicinae = {
    enable = true;

    # From nixpkgs-unstable (0.27.4 at the current lock), prebuilt in
    # cache.nixos.org. nixpkgs 26.05 still ships 0.23.2; both parse the TOML
    # theme format, which landed in 0.15.0.
    package = upkgs.vicinae;

    systemd = {
      enable = true;
      target = "sway-session.target";
    };

    themes = {
      horizon-dark = mkTheme "dark" colors.dark;
      horizon-light = mkTheme "light" colors.light;
    };

    settings = {
      # Vicinae picks light or dark itself, from the XDG portal color-scheme
      # that darkman already drives through dconf. No darkman script needed.
      theme = {
        dark = {
          name = "horizon-dark";
          icon_theme = "Papirus-Dark";
        };
        light = {
          name = "horizon-light";
          icon_theme = "Papirus-Light";
        };
      };

      font.normal = {
        family = "JetBrainsMono Nerd Font";
        size = 14;
      };

      launcher_window.opacity = 0.9;
    };
  };
}
