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

  # Without a platform theme Qt never asks the portal what the system
  # appearance is: the server puts no org.freedesktop.portal.Settings call on
  # the bus at all (verified with dbus-monitor across a restart),
  # QStyleHints::colorScheme stays Unknown and vicinae resolves that to its
  # dark theme - so the launcher stayed black all through light mode, even
  # after a restart. `gnome` is the built-in theme that does the portal
  # lookup: with it the server ReadAll's the portal at startup and follows
  # colorSchemeChanged afterwards, so darkman's own portal backend drives the
  # switch live. Scoped to this service rather than set session-wide, because
  # it would change how every other Qt app resolves its theme too.
  systemd.user.services.vicinae.Service.Environment = [ "QT_QPA_PLATFORMTHEME=gnome" ];

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
      # Vicinae picks light or dark itself, from Qt's
      # QStyleHints::colorScheme() - which only reaches the XDG portal when a
      # platform theme is loaded, hence QT_QPA_PLATFORMTHEME on the service
      # below. No darkman script: Qt follows SettingChanged live.
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

      launcher_window = {
        opacity = 1;

        # Sway stacks fullscreen windows above the 'top' layer, so the default
        # leaves the launcher hidden behind a fullscreen app. 'overlay' is the
        # only other layer vicinae accepts, and sway draws it above fullscreen.
        layer_shell.layer = "overlay";
      };
    };
  };
}
