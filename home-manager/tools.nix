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
    poweralertd
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

    # Dev related
    gccgo14
    python3
    dotnetCorePackages.sdk_9_0
    direnv
    gnumake
    wakatime-ls
  ];
}
