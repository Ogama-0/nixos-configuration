{ cfg, ... }:

let
  mkBasicJob = { paths, repo }: {
    inherit paths;
    patterns = [
      "- ${cfg.path.SSD_path}/.Trash-1000" # don't backup trash
      "- ${cfg.path.SSD_path}/lost+found"
    ];
    startAt = "daily";
    compression = "auto,zstd";
    environment.BORG_RSH = "ssh -i ${cfg.ssh.path.pub}";
    inherit repo;
    encryption.mode = "none";
    prune.keep = {
      within = "1d";
      daily = 1;
      weekly = 1;
      monthly = 1;
    };
  };

in {
  services.borgbackup = {

    jobs = {
      "ssd-backup" = mkBasicJob {
        paths = cfg.path.SSD_path;
        repo = cfg.path.backup.SSD_path;
      };

      "hdd-share-public-backup" = mkBasicJob {
        paths = cfg.path.hdd.share.public_HDD_path;
        repo = cfg.path.backup.hdd.share.public_HDD_path;
      };

      "hdd-app-immich-backup" = mkBasicJob {
        paths = cfg.path.hdd.app.immich;
        repo = cfg.path.backup.hdd.app.immich;
      };

      "hdd-app-jellyfin-backup" = mkBasicJob {
        paths = cfg.path.hdd.app.jellyfin;
        repo = cfg.path.backup.hdd.app.jellyfin;
      };

      "hdd-documents-backup" = mkBasicJob {
        paths = cfg.path.hdd.documents;
        repo = cfg.path.backup.hdd.documents;
      };
    };

    repos = {

      # --------- LOCAL --------- #

      "ssd-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = /mnt/backup/ssd-backup;
      };

      "hdd-share-public-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = cfg.path.backup.hdd.share.public_HDD_path;
      };

      "hdd-app-immich-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = cfg.path.backup.hdd.app.immich;
      };

      "hdd-app-jellyfin-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = cfg.path.backup.hdd.app.jellyfin;
      };

      "hdd-documents-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = cfg.path.backup.hdd.documents;
      };
      # --------- REMOTE --------- #
      "pc-perso-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = /mnt/backup/pc-perso-backup;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /mnt/backup/ssd-backup               0755 borg users -"
    "d /mnt/backup/hdd-backup               0755 borg users -"
    "d /mnt/backup/pc-perso-backup          0755 borg users -"
    "d /mnt/backup/pc-perso-backup/document 0755 borg users -"
  ];
  users.users.borg = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILaKjKo1kaGVYdA5U6kvrjhDj1T3tp04CmiZE3YmA7id ogama@nixos"
    ];
  };

}
