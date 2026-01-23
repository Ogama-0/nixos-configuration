{ cfg, ... }:
let
  inherit (cfg.path) SSD_path HDD_path;

  backup = cfg.path.backup.path;
in {

  fileSystems."${SSD_path}" = {
    device = "/dev/disk/by-uuid/251634ee-7ca6-4d69-81b4-5348f1dd3ef1";
    fsType = "ext4";
  };

  fileSystems."${HDD_path}" = {
    device = "/dev/disk/by-uuid/8f067717-34ae-4f64-b2ed-b674c6d388b3";
    fsType = "ext4";
  };
  fileSystems."${backup}" = {
    device = "/dev/disk/by-uuid/f105b93a-a670-40da-9af2-8b6b2c322d9a";
    fsType = "ext4";
  };

  systemd.tmpfiles.rules = [
    "d ${SSD_path} 0755 ${cfg.user} users -"
    "d ${HDD_path} 0755 ${cfg.user} users -"
    "d ${backup} 0755 ${cfg.user} users -"
  ];

}
