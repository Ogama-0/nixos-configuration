{ ... }:

{
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 30d";
  };

  services.upower = {
    enable = true;
    percentageLow = 10;
    percentageCritical = 5;
    timeCritical = 30;
  };
  environment.variables = {
    GLOBAL_TP_DIRECTORY = "/home/ogama/documents/epita/prog/tp/S2";
    EPITA_LOGIN = "oscar.cornut";
    PATH_SCRIPTS = "/home/ogama/nixos-configuration/scripts";
    PATH_NAS = "/home/ogama/documents/nas/smb_oscar";

  };
  # nautilus
  services.gvfs.enable = true;
}
