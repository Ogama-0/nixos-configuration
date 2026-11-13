{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.dev.epitaTools.enable = lib.mkEnableOption "the extra toolchain the school practicals need";
    };
in
{
  flake.featureModules.nixos.epitaTools = sharedOptions;

  flake.featureModules.home.epitaTools =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.dev.epitaTools.enable (
        {
          home.packages = with pkgs; [ wdisplays pavucontrol criterion ];
        }
      );
    };
}
