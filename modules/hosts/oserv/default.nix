# The oserv profile: home server, NixOS + Home Manager.
{ config, inputs, pkgs, upkgs, lpkgs, system, ... }:
{
  flake.nixosConfigurations.oserv = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs lpkgs upkgs; };
    modules = [
      config.flake.nixosModules.featuresNixos
      ./_configuration.nix
      inputs.nixos-hardware.nixosModules.dell-optiplex-3050
      inputs.sops-nix.nixosModules.sops
    ];
  };

  flake.homeConfigurations.oserv = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      wakatime-ls = inputs.wakatime-ls.packages.${pkgs.system}.default;
      inherit inputs pkgs lpkgs;
    };
    modules = [
      config.flake.homeModules.featuresHome
      ./_home.nix
      inputs.sops-nix.homeManagerModules.sops
    ];
  };
}
