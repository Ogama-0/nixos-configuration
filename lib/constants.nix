# Values needed both inside the module system and before it exists.
#
# `ogama.server.domain` and `ogama.server.paths.*` take their defaults from
# here, so a module reads them off `config` like any other option. But
# `packages.calino` bakes its siteUrl into the build (see pkgs/calino.nix),
# which happens where packages are defined — outside any module evaluation,
# where there is no `config` to read. One source, two consumers.
{
  domain = "ogama.me";

  paths = {
    ssd = "/mnt/ssd";
    hdd = "/mnt/hdd";
    backup = "/mnt/backup";
  };
}
