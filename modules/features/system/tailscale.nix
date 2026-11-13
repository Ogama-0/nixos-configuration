{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.tailscale.enable = lib.mkEnableOption "the tailscale client and its firewall rules";
    };
in
{
  flake.featureModules.nixos.tailscale =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.tailscale.enable (
        {
          services.tailscale = {
            enable = true;
            openFirewall = true;
          };
        }
      );
    };

  flake.featureModules.home.tailscale = sharedOptions;
}
