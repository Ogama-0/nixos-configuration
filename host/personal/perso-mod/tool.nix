{ pkgs, upkgs, lpkgs, ... }: {

  home.packages = with pkgs; [

    # Main pkgs
    # upkgs.zen-browser
    firefox
    vesktop
    spotify
    gimp
    bitwarden-desktop
    nautilus
    # stremio
    qbittorrent
    notify-desktop
    shotcut

    # Utility

    lpkgs.librepods
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
    fuse-overlayfs # sandbox
    bubblewrap # ...
    psmisc

    # game
    modrinth-app
    steam
    prismlauncher
    steam-run
    sc-controller
    superTuxKart
    mindustry
    wineWowPackages.full
    gamescope

    # Dev
    jetbrains-toolbox
    octaveFull
    gnumake
    rustup # rust
    python3 # Python
    dotnetCorePackages.sdk_9_0 # C#

    # Troll 
    cmatrix
    hollywood
  ];

}
