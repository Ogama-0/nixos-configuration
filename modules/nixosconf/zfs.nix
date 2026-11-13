{ ... }:

{
  # Enables the kernel module + zpool/zfs tooling. Needed before `zpool
  # create` can run at all, and before any `fileSystems` entry with
  # fsType = "zfs" can be added.
  boot.supportedFilesystems = [ "zfs" ];

  # ZFS refuses to import a pool without this (used to detect a pool
  # imported on two hosts at once). Generated once with
  # `head -c4 /dev/urandom | od -A none -t x4`, stays fixed for the life of
  # this host.
  networking.hostId = "22a89261";

  # Pools created against /dev/sdX names can come back DEGRADED/FAULTED
  # after a reboot reorders device letters. by-id names are stable across
  # reboots and across the sda/sdd USB-vs-SATA distinction.
  boot.zfs.devNodes = "/dev/disk/by-id";

  # Root here is ext4, not zfs, so this only affects the backup pool: with
  # force import on (the current default), a pool that wasn't cleanly
  # exported before a reboot gets imported anyway, silently skipping the
  # check that would otherwise flag possible corruption.
  boot.zfs.forceImportRoot = false;

  # Unset, ARC targets up to (almost) all of RAM for cache — fine on a
  # dedicated ZFS box, not here where jellyfin/immich/etc. share the same
  # 62G. 16G leaves headroom for everything else. Also poked live via
  # `echo 17179869184 > /sys/module/zfs/parameters/zfs_arc_max` so it
  # takes effect immediately instead of only after the next reboot.
  boot.extraModprobeConfig = "options zfs zfs_arc_max=17179869184";
}
