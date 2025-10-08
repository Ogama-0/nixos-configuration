{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    nixpie.url = "git+https://gitlab.cri.epita.fr/forge/infra/nixpie.git";
    nixpie.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpie }:
    let
      inherit (nixpkgs.lib) genAttrs;

      forAllSystems =
        genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllPkgs = function: forAllSystems (system: function pkgs.${system});

      pkgs = forAllSystems (system:
        (import nixpkgs {
          inherit system;
          overlays = [ ];
        }));
    in {
      formatter = forAllPkgs (pkgs: pkgs.nixpkgs-fmt);

      devShells = forAllPkgs (pkgs:
        with pkgs.lib; {
          default = pkgs.mkShell rec {
            nativeBuildInputs = [
              nixpie.packages.${pkgs.system}.m68k
              # nixpie.packages.${pkgs.system}.geany
              pkgs.xterm
              # pkgs.binutils-m68k
            ];

            buildInputs = [ ];

            LD_LIBRARY_PATH = makeLibraryPath buildInputs;
          };
        });
    };
}

