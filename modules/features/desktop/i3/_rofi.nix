# Part of the i3 feature. Its default.nix imports this unconditionally —
# imports instruct the module system and cannot be conditional — so the
# gate lives here instead.
{ config, lib, pkgs, ... }:
{
  config = lib.mkIf config.ogama.desktop.i3.enable (
    {
      # Keybindings i3
      xsession.windowManager.i3.config.keybindings = lib.mkOptionDefault {
        "Mod4+d" = "exec rofi -show drun";
        "Mod4+Shift+d" = "exec rofi -show run";
      };

      # Rofi program
      programs.rofi = {
        enable = true;
        theme = ../../../../scripts/rofi/epitheme.rasi;
        # theme = ../../../../scripts/rofi/epitheme_rect.rasi;
      };
    }
  );
}
