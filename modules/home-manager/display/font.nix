{ pkgs, ... }:

{
  home.packages = with pkgs; [
    noto-fonts
    noto-fonts-emoji
    nerd-fonts.jetbrains-mono
    nerd-fonts.ubuntu-mono
    nerd-fonts.caskaydia-cove
    font-awesome
    merriweather
    inter
    monocraft
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      serif = [ "Noto Sans" "Merriweather" ];
      sansSerif = [ "Inter" ];
      # monospace = [ "monocraft" ];
      monospace = [ "JetBrainsMonoNerdFont-Regular" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
