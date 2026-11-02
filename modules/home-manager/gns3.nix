{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gns3-gui
    gns3-server
    dynamips
    inetutils
  ];
}
