{

  description = "main nixos configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    wakatime-ls.url = "github:mrnossiom/wakatime-ls";
    wakatime-ls.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      nixosConfigurations = {
        personal = lib.nixosSystem {
          inherit pkgs;
          modules = [ nixosconf/configuration.nix ];
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
