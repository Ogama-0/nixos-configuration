{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.localsend.enable = lib.mkEnableOption "LocalSend and the firewall holes it needs";
    };
in
{
  flake.featureModules.nixos.localsend =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.localsend.enable (
        {
          programs.localsend = {
            enable = true;
            openFirewall = true;
          };
        }
      );
    };

  flake.featureModules.home.localsend = sharedOptions;
}
