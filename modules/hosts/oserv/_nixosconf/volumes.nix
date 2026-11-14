{ config, ... }:
let
  inherit (config.ogama.server.path) SSD_path HDD_path;

  backup = config.ogama.server.path.backup.path;
in {

  fileSystems."${SSD_path}" = {
    device = "/dev/disk/by-uuid/251634ee-7ca6-4d69-81b4-5348f1dd3ef1";
    fsType = "ext4";
  };

  # sdd merged into one partition spanning the full 3.6T disk, replacing
  # the old sdd1 (hdd-tmp data) + sdd2 (backup, now the zpool below) split.
  fileSystems."${HDD_path}" = {
    device = "/dev/disk/by-uuid/a64279e1-2f2d-49ad-9c8b-bf22fb4442c6";
    fsType = "ext4";
  };

  # zpool "backup" (sda + sdc, stripe). Pool created manually (zpool create
  # is not a NixOS option); import/mount from here on is declarative.
  fileSystems."${backup}" = {
    device = "backup";
    fsType = "zfs";
  };

  systemd.tmpfiles.rules = [
    "d ${SSD_path} 0755 ${config.ogama.identity.user} users -"
    "d ${HDD_path} 0755 ${config.ogama.identity.user} users -"
    # root, not the login user, and that is load-bearing. systemd-tmpfiles
    # refuses to resolve a path through a directory owned by a *different*
    # non-root user and silently skips the rule — so while this was owned by the
    # login user, every borg-owned rule under it in
    # backup-server.nix was a no-op ("Detected unsafe path transition
    # /mnt/backup (owned by ...) -> /mnt/backup/hdd-backup (owned by borg)").
    # The repository tree survived only because the directories already
    # existed; the day one did not, the job died at 226/NAMESPACE instead of
    # being recreated, which is exactly what happened on 11 November 2026 when
    # a switch tore down the pool import. A root parent is safe for any owner.
    "d ${backup} 0755 root root -"
  ];

}
