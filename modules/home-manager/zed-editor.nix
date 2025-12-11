{ pkgs, ... }: {
  programs.zed-editor = {
    enable = true;

    extensions =
      [ "nix" "html" "python" "dockerfile" "horizon" "latex" "C#" "wakatime" ];

    userSettings = {
      "auto_install_extensions" = {
        "html" = true;
        "dockerfile" = true;
        "docker-compose" = true;
        "python" = true;
        "horizon" = true;
        "LaTeX" = true;
        "c" = true;
        "c#" = true;
        "nix" = true;
        "wakatime" = true;

      };

      "base_keymap" = "JetBrains";

      # "theme" = {
      #   "mode" = "system";
      #   "light" = "Horizon";
      #   "dark" = "Horizon";
      # };

    };
  };
}
