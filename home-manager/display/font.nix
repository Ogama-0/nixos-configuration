{ pkgs, ... }:

{
  home.packages = with pkgs; [
    noto-fonts
    noto-fonts-emoji
    # nerd-fonts.jetbrains-mono
    # nerdfonts.cascadia-code
    font-awesome
    merriweather
    inter
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      serif = [ "Noto Sans" "Merriweather" ];
      sansSerif = [ "Inter" ];
      monospace = [ "JetBrainsMonoNerdFont-Regular" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
