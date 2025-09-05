{ lib, pkgs, ... }: {
  # Keybindings i3
  xsession.windowManager.i3.config.keybindings = lib.mkOptionDefault {
    "Mod4+d" = "exec rofi -show drun";
    "Mod4+Shift+d" = "exec rofi -show run";
  };

  # Rofi program
  programs.rofi = {
    enable = true;
    theme = "../../../scripts/rofi/bibjaw_1.rasi";
    # theme = "../../../scripts/rofi/ahsan.rasi";
    # theme = "../../../scripts/rofi/bibjaw_mini.rasi";
    # theme = "../../../scripts/rofi/bibjaw_floating.rasi";
  };
}

