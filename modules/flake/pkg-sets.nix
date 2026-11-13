# The package sets every host is built from.
#
# These were `let` bindings in flake.nix and specialArgs entries on each of the
# six configurations. They are now computed once and handed to other
# flake-parts modules through `_module.args`; each host's default.nix passes
# them on to its own module system via specialArgs / extraSpecialArgs, because
# a flake-parts `_module.args` does not reach into a NixOS or Home Manager
# evaluation.
{ inputs, ... }:
let
  system = "x86_64-linux";

  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfreePredicate = _: true;
  };

  # Attribute order matters and is preserved from the original: nixpkgs-unstable
  # is the right operand, so where it carries a package of the same name it wins
  # over the flake input listed on the left.
  upkgs = (
    {
      zen-browser = inputs.zen-browser.packages.${system}.default;
      quickshell = inputs.quickshell.packages.${system}.default;
    }
    // import inputs.nixpkgs-unstable { inherit system; }
  );

  # This repo's own packages, defined here rather than in packages.nix so that
  # both the flake output and the hosts that consume them read one definition.
  localPackages = {
    librepods = pkgs.callPackage ../../pkgs/librepods.nix { };
    deezer-cli = pkgs.callPackage ../../pkgs/deezer-cli.nix { };
    corpta-font = pkgs.callPackage ../../pkgs/corpta-font.nix { };
    orbitron-font = pkgs.callPackage ../../pkgs/orbitron-font.nix { };
    greetd-proxy = pkgs.callPackage ../../pkgs/greetd-proxy.nix { };
    # siteUrl is baked into the build (see pkgs/calino.nix), so it has to be
    # known here rather than in the module that serves it — which is why the
    # domain lives in lib/constants.nix and not only in an option.
    calino = pkgs.callPackage ../../pkgs/calino.nix {
      siteUrl = "http://calino.tail.${(import ../../lib/constants.nix).domain}";
    };
    # Unstable's callPackage, not the repo's default `pkgs`: `quickshell` and
    # `qt6` have to come from the same nixpkgs that upkgs.quickshell actually
    # resolves to, or the wrapped QtMultimedia is a version
    # `import QtMultimedia` loads but QMediaPlayer refuses.
    quickshell-multimedia =
      (import inputs.nixpkgs-unstable { inherit system; }).callPackage ../../pkgs/quickshell-multimedia.nix
        { };
  };
in
{
  _module.args = {
    inherit system pkgs upkgs localPackages;
    lpkgs = localPackages;
  };
}
