{ cfg, ... }: {

  fileSystems."${cfg.SSD_path}" = {
    device = "/dev/disk/by-uuid/251634ee-7ca6-4d69-81b4-5348f1dd3ef1";
    fsType = "ext4";
  };

  fileSystems."${cfg.HDD_path}" = {
    device = "/dev/disk/by-uuid/8f067717-34ae-4f64-b2ed-b674c6d388b3";
    fsType = "ext4";
  };

  systemd.tmpfiles.rules = [
    "d ${cfg.SSD_path} 0755 ${cfg.user} users -"
    "d ${cfg.HDD_path} 0755 ${cfg.user} users -"
  ];

}
