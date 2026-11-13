# Temporary scaffolding, deleted in the shared-options task.
#
# host/profiles.nix is still the source of per-host data at this point. It is
# handed to the host modules through `_module.args` so that flake.nix carries
# no host data of its own; the next task replaces every read of it with a
# declared `ogama.*` option and deletes both this file and profiles.nix.
{ ... }:
{
  _module.args.profiles = import ../../host/profiles.nix;
}
