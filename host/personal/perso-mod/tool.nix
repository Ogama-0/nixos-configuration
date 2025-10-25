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
    shotcut

    # Utility
    simplescreenrecorder
    mpv # View video files
    imv # ''
    wdisplays # display manager
    pavucontrol # audio managment
    networkmanagerapplet # network managment
    wl-color-picker
    wl-clipboard
    notify-desktop # notify sender
    mkvtoolnix
    libnotify # notify sender
    poweralertd
    dconf # use by Gnome environnement
    imv # image viewer for Wayland
    xdg-utils # don't know why this is here Kappa
    playerctl # audio flux controler
    mcrcon # rcon for minecraft

    # game
    modrinth-app
    steam
    prismlauncher
    steam-run
    steamcontroller
    superTuxKart
    mindustry

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
