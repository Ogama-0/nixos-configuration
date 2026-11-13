{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.core.nixGc.enable = lib.mkEnableOption "automatic nix store garbage collection for this user";
    };
in
{
  flake.featureModules.nixos.nixGc = sharedOptions;

  flake.featureModules.home.nixGc =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.core.nixGc.enable (
        {
          # The system-level `nix.gc` (modules/nixosconf/utilities.nix) runs as root and
          # only prunes /nix/var/nix/profiles. Home Manager keeps its own generations in
          # ~/.local/state/nix/profiles, which root never touches — without this they
          # pile up indefinitely and pin every store path they ever referenced.
          nix.gc = {
            automatic = true;
            dates = "weekly";
            options = "--delete-older-than 30d";
          };
        }
      );
    };
}
