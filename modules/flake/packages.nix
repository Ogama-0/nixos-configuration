# Exposes this repo's packages as flake outputs. The definitions live in
# pkg-sets.nix, because the hosts consume them too.
{ system, localPackages, ... }:
{
  flake.packages.${system} = localPackages;
}
