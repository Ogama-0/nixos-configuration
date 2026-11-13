# The oserv profile: home server, NixOS + Home Manager.
{ inputs, pkgs, upkgs, lpkgs, system, profiles, ... }:
{
  flake.nixosConfigurations.oserv = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      cfg = profiles.cfg-server;
      inherit inputs lpkgs upkgs;
    };
    modules = [
      ./_configuration.nix
      inputs.nixos-hardware.nixosModules.dell-optiplex-3050
      inputs.sops-nix.nixosModules.sops
    ];
  };

  flake.homeConfigurations.oserv = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      wakatime-ls = inputs.wakatime-ls.packages.${pkgs.system}.default;
      cfg = profiles.cfg-server;
      inherit inputs pkgs lpkgs;
    };
    modules = [
      ./_home.nix
      inputs.sops-nix.homeManagerModules.sops
    ];
  };
}
