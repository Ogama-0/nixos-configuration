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
      cfg-server = {
        user = "ogama_serv";
        home_path = "/home/${cfg-server.user}";
        mail = "oscar.cornut@gmail.com";
      };
      cfg-perso = {
        user = "ogama";
        home_path = "/home/${cfg-perso.user}";
        mail = "oscar.cornut@gmail.com";
      };
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
          specialArgs = { cfg = cfg-perso; };
          modules = [
            ./personal/configuration.nix
            nixos-hardware.nixosModules.lenovo-ideapad-15ach6
          ];
        };
        oserv = lib.nixosSystem {
          inherit system;
          specialArgs = { cfg = cfg-server; };
          modules = [ ./serveur/configuration.nix ];
        };
      };
      homeConfigurations = {
        personal = home-manager.lib.homeManagerConfiguration {
          extraSpecialArgs = {
            wakatime-ls = inputs.wakatime-ls.packages.${system}.default;
            cfg = cfg-perso;
          };
          inherit pkgs;
          modules = [ ./personal/home.nix ];
        };
        oserv = home-manager.lib.homeManagerConfiguration {
          extraSpecialArgs = {
            wakatime-ls = inputs.wakatime-ls.packages.${system}.default;
            cfg = cfg-server;
          };
          inherit pkgs;
          modules = [ ./serveur/home.nix ];
        };
      };
    };
}
