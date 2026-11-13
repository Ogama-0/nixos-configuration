{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.printer.enable = lib.mkEnableOption "CUPS and printer discovery";
    };
in
{
  flake.featureModules.nixos.printer =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.printer.enable (
        {
          services.printing = {
            enable = true;
            drivers = [ pkgs.brlaser ];
          };
          # hardware.printers = {
          #   ensureprinters = {

          #   };
          # };
        }
      );
    };

  flake.featureModules.home.printer = sharedOptions;
}
