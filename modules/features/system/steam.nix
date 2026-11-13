{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.steam.enable = lib.mkEnableOption "Steam and its 32-bit graphics stack";
    };
in
{
  flake.featureModules.nixos.steam =
    { config, lib, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.steam.enable (
        {
          hardware.steam-hardware.enable = true;
          programs.steam = {
            enable = true;
            remotePlay.openFirewall =
              true; # Open ports in the firewall for Steam Remote Play
            dedicatedServer.openFirewall =
              true; # Open ports in the firewall for Source Dedicated Server
            localNetworkGameTransfers.openFirewall =
              true; # Open ports in the firewall for Steam Local Network Game Transfers
          };
        }
      );
    };

  flake.featureModules.home.steam = sharedOptions;
}
