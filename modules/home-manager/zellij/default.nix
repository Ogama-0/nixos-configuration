{ ... }: {

  programs.zellij = {
    enable = true;
    enableFishIntegration = true;
  };

  xdg.configFile."zellij/config.kdl".source = ./config.kdl;
}
