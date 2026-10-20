{ pkgs, ... }:
{
  # Phone link for the panel's Mobile zone
  # (quickshell/components/panel/MobileModel.qml).
  #
  # The NixOS option rather than just the package: pairing needs TCP and UDP
  # 1714-1764 open, and a paired phone that cannot reach the daemon looks
  # exactly like no phone at all.
  programs.kdeconnect = {
    enable = true;
    package = pkgs.kdePackages.kdeconnect-kde;
  };
}
