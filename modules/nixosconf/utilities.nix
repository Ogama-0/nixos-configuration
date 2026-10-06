{ ... }:

{
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 30d";
  };

  # Hardlink identical files in the store. `auto-optimise-store` covers newly
  # built paths, the timer catches everything that predates it.
  nix.settings.auto-optimise-store = true;
  nix.optimise.automatic = true;

  services.power-profiles-daemon.enable = true;
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
  documentation.man.cache.enable = false;
}
