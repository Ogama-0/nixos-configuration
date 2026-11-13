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
      config.flake.nixosModules.featuresNixos
      ./_configuration.nix
      # Every feature is imported into every NixOS host now, and one of them
      # (samba) defines sops.secrets. An option definition has to resolve even
      # when its mkIf condition is false, so the host that never had sops still
      # needs the module that declares the option.
      inputs.sops-nix.nixosModules.sops
    ];
  };

  flake.homeConfigurations.personal = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      wakatime-ls = inputs.wakatime-ls.packages.${pkgs.system}.default;
      inherit inputs pkgs upkgs lpkgs;
    };
    modules = [
      config.flake.homeModules.featuresHome
      ./_home.nix
      inputs.sops-nix.homeManagerModules.sops
    ];
  };
}
