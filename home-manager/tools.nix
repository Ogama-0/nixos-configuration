{ pkgs, wakatime-ls, ... }:

{
  home.packages = with pkgs; [
    # Tool
    libnotify
    brightnessctl
    wl-clipboard
    killall
    networkmanagerapplet
    poweralertd
    dconf
    openssl
    fastfetch
    pkg-config
    imv
    xdg-utils
    playerctl
    wl-color-picker
    notify-desktop

    # App Tool Cli
    tlrc
    trash-cli
    mkvtoolnix
    zip
    unzip
    mcrcon
    ascii
    nmap
    ripgrep

    # App Tool Tui
    btop

    # App Tool Gui
    stremio # streeming
    simplescreenrecorder
    mpv # View video files
    wdisplays # display manager
    qbittorrent # torrent downloader
    pavucontrol # audio managment

    # Troll 
    cmatrix
    hollywood

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
