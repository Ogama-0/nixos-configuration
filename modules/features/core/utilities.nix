{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.core.utilities.enable = lib.mkEnableOption "store GC, base packages and other machine-wide housekeeping";
    };
in
{
  flake.featureModules.nixos.utilities =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.core.utilities.enable (
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
            GLOBAL_TP_DIRECTORY = "${config.ogama.identity.homePath}/documents/epita/prog/tp/S2";
            # Not from `cfg`: this module gets cfg-perso, which has no `login` -
            # that field only exists on cfg-epita. Reaching across profiles for it
            # would be worse than the literal.
            EPITA_LOGIN = "oscar.cornut";
            PATH_SCRIPTS = "${config.ogama.identity.homePath}/nixos-configuration/scripts";
            # Stale: nothing in this config mounts here. samba-cli.nix puts the
            # shares under `${config.ogama.share.path}` instead.
            PATH_NAS = "${config.ogama.identity.homePath}/documents/nas/smb_oscar";
          };
          # nautilus
          services.gvfs.enable = true;
          # documentation.enable = true;
          # documentation.man.enable = true;
          # documentation.man.generateCaches = true;
          # documentation.dev.enable = true;
        }
      );
    };

  flake.featureModules.home.utilities = sharedOptions;
}
