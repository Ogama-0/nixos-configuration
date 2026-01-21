{ cfg, ... }: {
  services.borgbackup = {

    jobs = {
      "ssd-backup" = {
        paths = "${cfg.SSD_path}";
        patterns = [
          "- ${cfg.SSD_path}/.Trash-1000" # don't backup trash
          "- ${cfg.SSD_path}/lost+found"
        ];
        startAt = "daily";
        compression = "auto,zstd";
        environment.BORG_RSH = "ssh -i ${cfg.ssh.path.pub}";
        repo = "/mnt/backup/ssd-backup";
        encryption.mode = "none";
        prune.keep = {
          within = "1d";
          daily = 7;
          weekly = 4;
          monthly = 2;
        };
      };
    };

    repos = {

      "ssd-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = /mnt/backup/ssd-backup;
      };

      "hdd-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = /mnt/backup/hdd-backup;
      };

      "pc-perso-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = /mnt/backup/pc-perso-backup;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /mnt/backup/ssd-backup      0755 borg users -"
    "d /mnt/backup/hdd-backup      0755 borg users -"
    "d /mnt/backup/pc-perso-backup 0755 borg users -"
  ];

}
