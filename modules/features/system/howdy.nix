{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.howdy.enable =
        lib.mkEnableOption "enable pam howdy for face recognition\
        for now, it's broken";
    };
in
{
  flake.featureModules.nixos.howdy =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.howdy.enable ({
        services.howdy = {
          enable = true;
          # settings = {
          # };
        };
        services.linux-enable-ir-emitter.enable = true;
      });
    };

  flake.featureModules.home.howdy = sharedOptions;
}
