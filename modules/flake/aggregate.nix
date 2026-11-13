# Imports every registered feature into every host of its kind.
#
# This is the whole of "selection is a config concern": a host does not choose
# which modules to import, it gets all of them and decides with
# `ogama.<domain>.<feature>.enable` what any of them actually does. A module
# nobody enables still evaluates, which is what stops one rotting unnoticed.
{ config, lib, ... }:
{
  flake.nixosModules.featuresNixos = {
    imports = lib.attrValues config.flake.featureModules.nixos;
  };

  flake.homeModules.featuresHome = {
    imports = lib.attrValues config.flake.featureModules.home;
  };
}
