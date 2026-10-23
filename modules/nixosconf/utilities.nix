{ cfg, ... }:

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
    GLOBAL_TP_DIRECTORY = "${cfg.home_path}/documents/epita/prog/tp/S2";
    # Not from `cfg`: this module gets cfg-perso, which has no `login` -
    # that field only exists on cfg-epita. Reaching across profiles for it
    # would be worse than the literal.
    EPITA_LOGIN = "oscar.cornut";
    PATH_SCRIPTS = "${cfg.home_path}/nixos-configuration/scripts";
    # Stale: nothing in this config mounts here. samba-cli.nix puts the
    # shares under `${cfg.share.path}` instead.
    PATH_NAS = "${cfg.home_path}/documents/nas/smb_oscar";
  };
  # nautilus
  services.gvfs.enable = true;
  documentation.enable = true;
  documentation.man.enable = true;
  documentation.man.generateCaches = true;
  documentation.dev.enable = true;
}
