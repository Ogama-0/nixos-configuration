# Option declarations for the outputs flake-parts does not know about.
#
# `flake.nixosModules` and `flake.nixosConfigurations` are flake-parts' own.
# Home Manager's equivalents are not, and neither are the two trees this repo
# adds:
#
#   featureModules  modules imported into EVERY host of their kind, gated on an
#                   `ogama.<domain>.<feature>.enable` option. Selection is a
#                   `config` concern, never an `imports` concern.
#
# Host entry modules are NOT registered here. They stay plain NixOS and Home
# Manager modules in _-prefixed files, referenced by path from their host's
# default.nix — which is the only flake-parts module in a host directory. That
# keeps the aggregator's job trivial (import every featureModule, full stop)
# with nothing to filter out.
{ lib, ... }:
let
  modulesOption =
    description:
    lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      inherit description;
    };
in
{
  options.flake = {
    featureModules = {
      nixos = modulesOption "NixOS feature modules, imported into every NixOS host and gated by an enable option.";
      home = modulesOption "Home Manager feature modules, imported into every Home Manager profile and gated by an enable option.";
    };

    homeConfigurations = modulesOption "Home Manager configurations.";
    homeModules = modulesOption "Home Manager modules exposed as flake outputs.";
  };
}
