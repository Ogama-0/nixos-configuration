{ lib, pkgs, ... }: {
  # Keybindings i3
  xsession.windowManager.i3.config.keybindings = lib.mkOptionDefault {
    "Mod4+d" = "exec rofi -show drun";
    "Mod4+Shift+d" = "exec rofi -show run";
  };

  # Rofi program
  programs.rofi = {
    enable = true;

    # TODO

  };
}

