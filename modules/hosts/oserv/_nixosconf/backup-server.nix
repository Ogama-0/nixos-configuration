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

      "hdd-document-backup" = mkBasicJob {
        paths = cfg.path.hdd.document;
        repo = cfg.path.backup.hdd.document;
      };
    };

    repos = {

      # --------- LOCAL --------- #

      "ssd-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = cfg.path.backup.SSD_path;
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

      "hdd-document-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = cfg.path.backup.hdd.document;
      };
      # --------- REMOTE --------- #
      "laptop-document-backup" = {
        authorizedKeys = [ cfg.ssh.pubkey ];
        path = cfg.path.backup.laptop.document;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${cfg.path.backup.SSD_path}                   0755 borg users -"

    "d ${cfg.path.backup.HDD_path}                   0755 borg users -"
    "d ${cfg.path.backup.hdd.document}              0755 borg users -"
    "d ${cfg.path.backup.hdd.share.path}             0755 borg users -"
    "d ${cfg.path.backup.hdd.share.public_HDD_path}  0755 borg users -"
    "d ${cfg.path.backup.HDD_app}                    0755 borg users -"
    "d ${cfg.path.backup.hdd.app.immich}             0755 borg users -"
    "d ${cfg.path.backup.hdd.app.jellyfin}           0755 borg users -"

    "d ${cfg.path.backup.laptop.path}                0755 borg users -"
    "d ${cfg.path.backup.laptop.document}            0755 borg users -"
  ];
  users.users.borg = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILaKjKo1kaGVYdA5U6kvrjhDj1T3tp04CmiZE3YmA7id ogama@nixos"
    ];
  };

}
