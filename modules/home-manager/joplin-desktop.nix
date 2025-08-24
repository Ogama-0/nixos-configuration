{ ... }: {
  programs.joplin-desktop = {
    enable = true;

    general.editor = "helix";
    # extra-Config = {
    #  https://mynixos.com/home-manager/option/programs.joplin-desktop.extraConfig
    # };
  };
}
