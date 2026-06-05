{
  pkgs,
  upkgs,
  lpkgs,
  ...
}:
{

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
    proton-vpn
    gnome-disk-utility
    testdisk
    lpkgs.free-claude-code

    # Utility

    lpkgs.librepods
    kooha # screen recorder rust
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
    shotcut

    # game
    modrinth-app
    steam
    prismlauncher
    steam-run
    sc-controller
    supertuxkart
    mindustry
    wineWow64Packages.full
    gamescope

    # Dev
    jetbrains-toolbox
    octaveFull
    gnumake
    rustup # rust
    python3 # Python
    dotnetCorePackages.sdk_9_0 # C#

    rstudio # R for tec
    R

    qemu # vm

    # Troll
    cmatrix
    hollywood
  ];

}
