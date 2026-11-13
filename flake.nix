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

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    import-tree.url = "github:vic/import-tree";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    quickshell.url = "github:quickshell-mirror/quickshell";
    quickshell.inputs.nixpkgs.follows = "nixpkgs-unstable";

    calendar-syncer.url = "git+ssh://git@github.com/pixilie/calendar_syncer";
    calendar-syncer.inputs.nixpkgs.follows = "nixpkgs-unstable";

    lsi-web-interface.url = "git+ssh://git@github.com/Ogama-0/lsi-web-interface";
    lsi-web-interface.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  # No host wiring, no package list, no specialArgs plumbing: import-tree
  # imports every .nix under the roots below, and each of those files registers
  # what it provides. Adding a module is adding a file.
  #
  # The roots are listed explicitly rather than as ./modules because
  # modules/{nixosconf,home-manager} still hold unported modules, which are
  # NixOS and Home Manager modules rather than flake-parts ones. The last
  # porting task removes those directories and this list collapses to ./modules.
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      imports = [
        (inputs.import-tree ./modules/flake)
        (inputs.import-tree ./modules/features)
        (inputs.import-tree ./modules/hosts)
      ];
    };
}
