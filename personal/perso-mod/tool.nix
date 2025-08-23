{ pkgs, ... }: {
  home.packages = with pkgs; [

    # Main pkgs
    firefox
    vesktop
    spotify
    gimp
    bitwarden-desktop
    nautilus
    stremio
    qbittorrent
    notify-desktop

    # Utility
    simplescreenrecorder
    mpv # View video files
    imv # ''
    wdisplays # display manager
    pavucontrol # audio managment
    networkmanagerapplet # network managment
    wl-color-picker
    notify-desktop # notify sender
    mkvtoolnix

    # game
    modrinth-app
    steam
    prismlauncher
    steam-run
    steamcontroller

    # Dev
    jetbrains-toolbox
    octaveFull
    unityhub
    gnumake
    rustup # rust
    python3 # Python
    dotnetCorePackages.sdk_9_0 # C#

    # Troll 
    cmatrix
    hollywood
  ];

}
