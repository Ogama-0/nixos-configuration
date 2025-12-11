{

  description = "main nixos configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    wakatime-ls.url = "github:mrnossiom/wakatime-ls";
    wakatime-ls.inputs.nixpkgs.follows = "nixpkgs";

    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
    zen-browser.inputs.home-manager.follows = "home-manager";

    stylix.url = "github:nix-community/stylix/release-25.11";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, home-manager, nixos-hardware, stylix, ... }@inputs:
    let
      profiles = import ./host/profiles.nix;
      inherit (profiles) cfg-server cfg-perso cfg-epita;
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = _: true;
      };
      lpkgs = { librepods = self.packages.${system}.librepods; };
      upkgs = {
        zen-browser = self.inputs.zen-browser.packages.${pkgs.system}.default;
      };
    in {
      templates = import ./templates;

      packages.${system} = {
        librepods = pkgs.callPackage ./pkgs/librepods.nix { };
      };

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
          modules = [
            ./host/serveur/configuration.nix
            nixos-hardware.nixosModules.dell-optiplex-3050
          ];
        };
      };

      homeConfigurations = {
        personal = home-manager.lib.homeManagerConfiguration {
          extraSpecialArgs = {
            wakatime-ls = inputs.wakatime-ls.packages.${system}.default;
            cfg = cfg-perso;
            inherit inputs;
            inherit pkgs;
            inherit upkgs;
            inherit lpkgs;
          };
          inherit pkgs;
          modules = [ ./host/personal/home.nix stylix.homeModules.stylix ];
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
