{ cfg, ... }:
let
  inherit (cfg.path) SSD_path HDD_path;

  backup = cfg.path.backup.path;
in {
  imports = [ ../../../modules/nixosconf/zfs.nix ];

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
    "d ${SSD_path} 0755 ${cfg.user} users -"
    "d ${HDD_path} 0755 ${cfg.user} users -"
    "d ${backup} 0755 ${cfg.user} users -"
  ];

}
