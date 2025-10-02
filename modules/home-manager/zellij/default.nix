{ ... }: {

  programs.zellij = {
    enable = true;
    enableFishIntegration = true;
  };

  xdg.configFile."zellij/config.kdl".source = ./config.kdl;
  xdg.configFile."zellij/layout/onbar.kdl".source = ./layout/nobar.kdl;
}
