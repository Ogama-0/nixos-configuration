{ pkgs, wakatime-ls, ... }:

{
  home.packages = with pkgs; [
    # Tool
    libnotify
    brightnessctl
    wl-clipboard
    killall
    poweralertd
    dconf
    openssl
    fastfetch
    pkg-config
    imv
    xdg-utils
    playerctl

    # App Tool Cli
    tlrc
    trash-cli
    zip
    unzip
    mcrcon
    ascii
    nmap
    ripgrep
    git

    # App Tool Tui
    btop

    # Dev related
    gccgo14 # C
    direnv
    gnumake
    wakatime-ls

  ];
}
