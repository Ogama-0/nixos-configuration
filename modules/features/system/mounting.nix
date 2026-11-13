{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.mounting.enable = lib.mkEnableOption "this host's extra filesystem mounts";
    };
in
{
  flake.featureModules.nixos.mounting =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.mounting.enable (
        {
          services.usbmuxd.enable = true;

          environment.systemPackages = with pkgs; [
            libimobiledevice
            ifuse # optional, to mount using 'ifuse'
          ];
        }
      );
    };

  flake.featureModules.home.mounting = sharedOptions;
}
