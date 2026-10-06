{ lib, pkgs, config, ... }:
let
  colors = import ../../lib/theme-colors.nix;

  tofiConfig = c: ''
    font = ${config.stylix.fonts.monospace.name}
    font-size = ${toString config.stylix.fonts.sizes.popups}

    horizontal = true
    anchor = top
    width = 100%
    height = 45

    padding-left = 20
    padding-top = 11

    outline-width = 0
    border-width = 0

    min-input-width = 100
    result-spacing = 20

    text-color = #${c.base05}
    background-color = #${c.base00}

    prompt-text = ${" "}
    prompt-padding = 30
    prompt-background = #${c.base02}
    prompt-background-corner-radius = 5
    prompt-background-padding = 4, 8

    input-color = #${c.base05}
    input-background = #${c.base02}
    input-background-corner-radius = 5
    input-background-padding = 4, 10

    selection-color = #${c.base0D}
    selection-background = #${c.base02}
    selection-match-color = #${c.base0B}
    selection-background-corner-radius = 5
    selection-background-padding = 4, 10

    clip-to-padding = false
    history = true
  '';
in
{
  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    "Mod4+d" = "exec tofi-drun | xargs swaymsg exec --";
    "Mod4+shift+d" = "exec tofi-run | xargs swaymsg exec --";
  };

  home.packages = [ pkgs.tofi ];

  xdg.configFile = {
    "tofi/config-dark".text = tofiConfig colors.dark;
    "tofi/config-light".text = tofiConfig colors.light;
  };

  home.activation.tofiConfigDefault = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/tofi/config-dark" "${config.xdg.configHome}/tofi/config"
  '';
}
