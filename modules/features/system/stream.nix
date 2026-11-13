{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.stream.enable = lib.mkEnableOption "streaming and capture support";
    };
in
{
  flake.featureModules.nixos.stream =
    { config, pkgs, lib, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.stream.enable (
        {
          xdg.portal = {
            enable = true;
            wlr.enable = true;
            extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
            config.common.default = "*";
          };

        }
      );
    };

  flake.featureModules.home.stream = sharedOptions;
}
