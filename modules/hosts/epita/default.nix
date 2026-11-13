# The EPITA school computer: Home Manager only, in two variants.
#
# `epita-light` is the same profile with a shorter imports list, so that it
# builds faster on a machine that rebuilds often. Both are registered here
# because they share this directory; the light variant stops being a separate
# file once the two are expressed as toggles.
{ inputs, pkgs, lpkgs, profiles, ... }:
let
  mkEpita = entry: inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      wakatime-ls = inputs.wakatime-ls.packages.${pkgs.system}.default;
      cfg = profiles.cfg-epita;
      inherit inputs pkgs lpkgs;
    };
    modules = [
      entry
      inputs.sops-nix.homeManagerModules.sops
    ];
  };
in
{
  flake.homeConfigurations.epita = mkEpita ./_home.nix;
  flake.homeConfigurations."epita-light" = mkEpita ./_home-light.nix;
}
