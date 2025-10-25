{ ... }:
let
  green = "#27d796";
  yellow = "#fab795";
  orange = "#f1895c";
  red = "#e95678";
in {
  programs.alacritty = {
    enable = true;

    settings = {
      window = { decorations = "buttonless"; };

      font = {
        size = 13.5;
        # normal.family = "UbuntuMonoNerdFont";
        # bold.family = "UbuntuMonoNerdFont";
        # italic.family = "UbuntuMonoNerdFont";
        normal.family = "JetBrainsMonoNerdFont";
        bold.family = "JetBrainsMonoNerdFont";
        italic.family = "JetBrainsMonoNerdFont";
      };
      terminal.shell = { program = "fish"; };
      colors = {
        # Default colors
        primary = {
          background = "#000000";
          foreground = "#fffaf3";
        };

        # Normal colors
        normal = {
          black = "#222222";
          inherit green; # red yellow;
          red = "#ff000f";
          # green = "#8ce00a";
          yellow = "#ffb900";
          blue = "#008df8";
          magenta = "#FF00FF";
          cyan = "#00d7eb";
          white = "#ffffff";
        };

        # Bright colors
        bright = {
          black = "#444444";
          red = "#ff273f";
          green = "#abe05a";
          yellow = "#ffd141";
          blue = "#0092ff";
          magenta = "#6c43a5";
          cyan = "#67ffef";
          white = "#ffffff";
        };
      };
    };
  };
}
