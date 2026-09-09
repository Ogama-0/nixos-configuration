{ pkgs, ... }: {
  home.packages = with pkgs; [ wdisplays pavucontrol criterion ];
}
