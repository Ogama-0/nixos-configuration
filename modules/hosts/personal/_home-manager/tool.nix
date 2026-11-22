{
  pkgs,
  upkgs,
  lpkgs,
  ...
}:
{

  # mpv has no built-in MPRIS support; the mpris script exposes one so
  # playerctl (and swayidle's idle inhibitor) can see when it's playing.
  programs.mpv = {
    enable = true;
    scripts = [ pkgs.mpvScripts.mpris ];
  };

  home.packages = with pkgs; [

    # Main pkgs
    firefox
    # google-chrome
    discord
    # vesktop
    # spotify
    deezer-enhanced
    gimp
    # bitwarden-desktop elecron issue : https://github.com/NixOS/nixpkgs/issues/528213
    nautilus
    upkgs.joplin-desktop
    # stremio
    qbittorrent
    notify-desktop
    shotcut
    proton-vpn
    gnome-disk-utility
    testdisk
    vlc
    claude-code

    # Android tools :
    android-tools

    # Utility

    lpkgs.librepods
    kooha # screen recorder rust
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
    fuse-overlayfs # sandbox
    bubblewrap # ...
    psmisc
    shotcut

    # game
    steam
    heroic
    prismlauncher
    mcrcon # rcon for minecraft
    steam-run
    sc-controller
    supertuxkart
    mindustry
    wineWow64Packages.full
    gamescope

    # Dev
    # jetbrains-toolbox
    # octaveFull
    gnumake
    rustup # rust
    # python3 # Python
    # dotnetCorePackages.sdk_9_0 # C#
    # R

    # Troll
    cmatrix
    hollywood
  ];

}
