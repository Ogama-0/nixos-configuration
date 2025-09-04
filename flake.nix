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
        SSD_path = "${cfg-server.home_path}/ssd";
        SSD_app = "${cfg-server.SSD_path}/appdata";
        HDD_path = "${cfg-server.home_path}/hdd";
        HDD_app = "${cfg-server.HDD_path}/appdata";
        server = { domain = "ogama.me"; };
      };
      cfg-perso = {
        user = "ogama";
        home_path = "/home/${cfg-perso.user}";
        mail = "oscar.cornut@gmail.com";
      };
      cfg-epita = {
        login = "oscar.cornut";
        user = "oscar.cornut";
        mail = "oscar.cornut@epita.fr";
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
            ./host/personal/configuration.nix
            nixos-hardware.nixosModules.lenovo-ideapad-15ach6
          ];
        };
        oserv = lib.nixosSystem {
          inherit system;
          specialArgs = { cfg = cfg-server; };
          modules = [ ./host/serveur/configuration.nix ];
        };
      };

      homeConfigurations = {

        personal = home-manager.lib.homeManagerConfiguration {
          extraSpecialArgs = {
            wakatime-ls = inputs.wakatime-ls.packages.${system}.default;
            cfg = cfg-perso;
            inherit inputs;
            inherit pkgs;
          };
          inherit pkgs;
          modules = [ ./host/personal/home.nix ];
        };

        oserv = home-manager.lib.homeManagerConfiguration {
          extraSpecialArgs = {
            wakatime-ls = inputs.wakatime-ls.packages.${system}.default;
            cfg = cfg-server;
            inherit inputs;
            inherit pkgs;
          };
          inherit pkgs;
          modules = [ ./host/serveur/home.nix ];
        };

        epita = home-manager.lib.homeManagerConfiguration {
          extraSpecialArgs = {
            inherit inputs;
            inherit pkgs;
            cfg = cfg-epita;
            wakatime-ls = inputs.wakatime-ls.packages.${system}.default;
          };
          inherit pkgs;
          modules = [ ./host/epita/epita.nix ];
        };
        epita-light = home-manager.lib.homeManagerConfiguration {
          extraSpecialArgs = {
            inherit inputs;
            inherit pkgs;
            cfg = cfg-epita;
            wakatime-ls = inputs.wakatime-ls.packages.${system}.default;
          };
          inherit pkgs;
          modules = [ ./host/epita/epita_light.nix ];
        };
      };
    };
}
