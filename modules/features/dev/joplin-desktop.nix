{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.dev.joplinDesktop.enable = lib.mkEnableOption "the Joplin desktop client";
    };
in
{
  flake.featureModules.nixos.joplinDesktop = sharedOptions;

  flake.featureModules.home.joplinDesktop =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.dev.joplinDesktop.enable (
        {
          programs.joplin-desktop = {
            enable = true;

            general.editor = "helix";
            # extra-Config = {
            #  https://mynixos.com/home-manager/option/programs.joplin-desktop.extraConfig
            # };
          };
        }
      );
    };
}
