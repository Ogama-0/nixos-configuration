# The personal profile: main desktop, NixOS + Home Manager.
#
# This is the only flake-parts module in the directory. Everything else here is
# a plain NixOS or Home Manager module in a _-prefixed file, invisible to
# import-tree and referenced by path below.
{ config, inputs, pkgs, upkgs, lpkgs, ... }:
{
  flake.nixosConfigurations.personal = inputs.nixpkgs.lib.nixosSystem {
    inherit pkgs;
    specialArgs = { inherit lpkgs upkgs; };
    modules = [
      config.flake.featureModules.nixos.sharedOptions
      ./_configuration.nix
    ];
  };

  flake.homeConfigurations.personal = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      wakatime-ls = inputs.wakatime-ls.packages.${pkgs.system}.default;
      inherit inputs pkgs upkgs lpkgs;
    };
    modules = [
      config.flake.featureModules.home.sharedOptions
      ./_home.nix
      inputs.sops-nix.homeManagerModules.sops
    ];
  };
}
