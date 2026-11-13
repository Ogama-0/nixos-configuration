{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.dev.gns3.enable = lib.mkEnableOption "the GNS3 network simulator client";
    };
in
{
  flake.featureModules.nixos.gns3 = sharedOptions;

  flake.featureModules.home.gns3 =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.dev.gns3.enable (
        {
          home.packages = with pkgs; [
            gns3-gui
            gns3-server
            dynamips
            inetutils
          ];
        }
      );
    };
}
