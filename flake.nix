{
  description = "main nixos configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    wakatime-ls.url = "github:mrnossiom/wakatime-ls";
    wakatime-ls.inputs.nixpkgs.follows = "nixpkgs";

    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs-unstable";
    zen-browser.inputs.home-manager.follows = "home-manager";


    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    quickshell.url = "github:quickshell-mirror/quickshell";
    quickshell.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # Private repo: fetched over SSH, so the key that reads it must be
    # available to whoever evaluates the flake. `sudo nixos-rebuild` runs
    # as root and has no such key — run the non-sudo
    # `nix build .#nixosConfigurations.oserv...` first (docs/adding-a-server-service.md
    # already prescribes this), which puts the input in the store where the
    # privileged evaluation finds it by narHash alone.
    calendar-syncer.url = "git+ssh://git@github.com/pixilie/calendar_syncer";
    calendar-syncer.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nixos-hardware,
      sops-nix,
      ...
    }@inputs:
    let
      profiles = import ./host/profiles.nix;
      inherit (profiles) cfg-server cfg-perso cfg-epita;
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = _: true;
      };
      lpkgs = {
        librepods = self.packages.${system}.librepods;
        corpta-font = self.packages.${system}.corpta-font;
        orbitron-font = self.packages.${system}.orbitron-font;
        greetd-proxy = self.packages.${system}.greetd-proxy;
        calino = self.packages.${system}.calino;
        # free-claude-code = self.packages.${system}.free-claude-code;
      };
      upkgs = (
        {
          zen-browser = self.inputs.zen-browser.packages.${pkgs.system}.default;
          quickshell = self.inputs.quickshell.packages.${pkgs.system}.default;
          # mindustry = self.inputs.nixpkgs-unstable.legacyPackages.${pkgs.system}.mindustry;
        }
        // import nixpkgs-unstable { inherit system; }
      );

    in
    {
      templates = import ./templates;

      packages.${system} = {
        librepods = pkgs.callPackage ./pkgs/librepods.nix { };
        corpta-font = pkgs.callPackage ./pkgs/corpta-font.nix { };
        orbitron-font = pkgs.callPackage ./pkgs/orbitron-font.nix { };
        greetd-proxy = pkgs.callPackage ./pkgs/greetd-proxy.nix { };
        # siteUrl is baked into the build (see pkgs/calino.nix), so it has to
        # be known here rather than in the module that serves it.
        calino = pkgs.callPackage ./pkgs/calino.nix {
          siteUrl = "http://calino.tail.${cfg-server.server.domain}";
        };
        # free-claude-code = pkgs.callPackage ./pkgs/freeclaudecode.nix { };
      };

      nixosConfigurations = {
        personal = lib.nixosSystem {
          inherit pkgs;
          specialArgs = {
            cfg = cfg-perso;
            inherit lpkgs upkgs;
          };
          modules = [ ./host/personal/configuration.nix ];
        };
        oserv = lib.nixosSystem {
          inherit system;
          specialArgs = {
            cfg = cfg-server;
            inherit inputs lpkgs upkgs;
          };
          modules = [
            ./host/serveur/configuration.nix
            nixos-hardware.nixosModules.dell-optiplex-3050
            sops-nix.nixosModules.sops
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
          modules = [
            ./host/personal/home.nix
            sops-nix.homeManagerModules.sops
          ];
        };

        oserv = home-manager.lib.homeManagerConfiguration {
          extraSpecialArgs = {
            wakatime-ls = inputs.wakatime-ls.packages.${system}.default;
            cfg = cfg-server;
            inherit inputs;
            inherit pkgs;
            inherit lpkgs;
          };
          inherit pkgs;
          modules = [
            ./host/serveur/home.nix
            sops-nix.homeManagerModules.sops
          ];
        };

        epita = home-manager.lib.homeManagerConfiguration {
          extraSpecialArgs = {
            inherit inputs;
            inherit pkgs;
            cfg = cfg-epita;
            wakatime-ls = inputs.wakatime-ls.packages.${system}.default;
            inherit lpkgs;
          };
          inherit pkgs;
          modules = [
            ./host/epita/epita.nix
            sops-nix.homeManagerModules.sops
          ];
        };
        epita-light = home-manager.lib.homeManagerConfiguration {
          extraSpecialArgs = {
            inherit inputs;
            inherit pkgs;
            cfg = cfg-epita;
            wakatime-ls = inputs.wakatime-ls.packages.${system}.default;
            inherit lpkgs;
          };
          inherit pkgs;
          modules = [
            ./host/epita/epita_light.nix
            sops-nix.homeManagerModules.sops
          ];
        };
      };
    };
}
