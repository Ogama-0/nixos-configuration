# The EPITA school computer: Home Manager only, in two variants.
#
# `epita-light` is the same profile with fewer features enabled, so that it
# builds faster on a machine that rebuilds often. Both share one entry module
# and differ only in which toggles file they are given.
{ config, inputs, pkgs, lpkgs, ... }:
let
  mkEpita =
    toggles:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        wakatime-ls = inputs.wakatime-ls.packages.${pkgs.system}.default;
        inherit inputs pkgs lpkgs;
      };
      modules = [
        config.flake.homeModules.featuresHome
        toggles
        ./_home.nix
        inputs.sops-nix.homeManagerModules.sops
      ];
    };
in
{
  flake.homeConfigurations.epita = mkEpita ./_toggles.nix;
  flake.homeConfigurations."epita-light" = mkEpita ./_toggles-light.nix;
}
