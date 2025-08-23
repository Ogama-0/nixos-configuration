{ pkgs, wakatime-ls, ... }:

{
  home.packages = with pkgs; [
    # Tool
    brightnessctl
    wl-clipboard
    killall
    openssl
    fastfetch
    pkg-config

    # App Tool Cli
    tlrc
    trash-cli
    zip
    unzip
    ascii
    nmap
    ripgrep

    # App Tool Tui
    btop

    # Dev related
    gccgo14 # C
    direnv
    gnumake
    wakatime-ls

  ];
}
