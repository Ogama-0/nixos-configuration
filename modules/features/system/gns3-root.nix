{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.gns3Root.enable = lib.mkEnableOption "the privileged half of GNS3";
    };
in
{
  flake.featureModules.nixos.gns3Root =
    { config, lib, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.gns3Root.enable (
        {
          users.groups.ubridge = { };

          security.wrappers.ubridge = {
            source = lib.getExe pkgs.ubridge;
            capabilities = "cap_net_raw,cap_net_admin=eip";
            owner = "root";
            group = "ubridge";
            permissions = "u=rwx,g=rx,o=r";
          };
        }
      );
    };

  flake.featureModules.home.gns3Root = sharedOptions;
}
