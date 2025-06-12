{ pkgs, wakatime-ls, ... }:

{
  home.packages = with pkgs; [
    brightnessctl
    wl-clipboard
    killall
    networkmanagerapplet
    unzip
    poweralertd
    dconf
    openssl
    wdisplays
    fastfetch
    pkg-config
    imv
    xdg-utils
    tlrc
    playerctl
    notify-desktop
    fastfetch
    btop
    simplescreenrecorder
    # vlc
    mpv
    trash-cli
    qbittorrent
    spotube
    mkvtoolnix
    pavucontrol
    mcrcon
    libnotify
    ascii
    nmap
    # Troll 
    cmatrix
    hollywood
    stremio

    # Dev related
    gccgo14
    python3
    dotnetCorePackages.sdk_9_0
    direnv
    gnumake
    wakatime-ls
    rustup

    # Games
    prismlauncher
  ];
}
