{ ... }: {
  services.earlyoom = {
    enable = true;
    freeSwapThreshold = 2;
    freeMemThreshold = 2;
    extraArgs = [
      "-g"
      "--avoid"
      "'^(X|init|Xorg|ssh|sway|gnome.*|alacritty|quickshell)$'"
      "--prefer"
      "'^(electron|libreoffice|gimp)$'"
    ];
  };

}
