{

  description = "ok on test";

  inputs = {
    nixpkgs = {
      url = "github:NixOs/nixpkgs/nixos-24.11";
    }
    
  };

  outputs = { self, nixpkgs, ...}:
  let 
    lib = nixpkgs.lib;
   in {
    nixosConfigurations = {
      OgamaNixOs = lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./configuration.nix ]
      }
    };
  };
}
