{ lib, ... }: {
  wayland.windowManager.sway.config.keybindings =
    lib.mkOptionDefault { "Mod4+d" = "exec tofi-run | xargs swaymsg exec --"; };

  programs.tofi = {
    enable = true;

    settings = {
      font = "CaskaydiaCoveNerdFont";
      font-size = 13;

      horizontal = true;
      anchor = "top";
      width = "100%";
      height = 45;

      padding-left = 20;
      # padding-left = 10;
      padding-top = 11;

      outline-width = 0;
      border-width = 0;

      min-input-width = 100;
      result-spacing = 20;

      text-color = "#ffffff";
      background-color = "#2e3244";

      prompt-text = " ";
      prompt-padding = 30;
      prompt-background = "#282c34";
      prompt-background-corner-radius = 5;
      prompt-background-padding = "4, 8";

      input-color = "#cccccc";
      input-background = "#282C34";
      input-background-corner-radius = 5;
      input-background-padding = "4, 10";

      selection-color = "#c5c6c6";
      selection-background = "#282C34";
      selection-background-corner-radius = 5;
      selection-match-color = "#f1895c";
      selection-background-padding = "4, 10";

      clip-to-padding = false;
      history = true;
    };
  };

}
