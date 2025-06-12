{

  description = "main nixos configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    wakatime-ls.url = "github:mrnossiom/wakatime-ls";
    wakatime-ls.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, home-manager, nixos-hardware, ... }@inputs:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = _: true;
      };
    in {
      nixosConfigurations = {
        personal = lib.nixosSystem {
          inherit pkgs;
          modules = [
            nixosconf/configuration.nix
            nixos-hardware.nixosModules.lenovo-ideapad-15ach6
          ];
        };
        nasogama = lib.nixosSystem {
          inherit system;
          modules = [ ./servconfig/nixosconf/configuration.nix ];
        };
      };
      homeConfigurations = {
        personal = home-manager.lib.homeManagerConfiguration {
          extraSpecialArgs = {
            wakatime-ls = inputs.wakatime-ls.packages.${system}.default;
          };
          inherit pkgs;
          modules = [ ./home-manager/home.nix ];
        };
      };
    };
}
