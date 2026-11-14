{ config,
  lib,
  ... }:

let
  mkBasicJob = { paths, repo }: {
    inherit paths;

    # Derived from `paths`, not from a fixed root. These two were hardcoded to
    # SSD_path, so every hdd-* job carried a pair of patterns that could never
    # match anything under its own source while the HDD's own trash was
    # archived unnoticed. Deriving them means a new job cannot reintroduce
    # that by copying the block.
    patterns = lib.concatMap (p: [
      "- ${p}/.Trash-1000" # don't backup trash
      "- ${p}/lost+found"
    ]) (lib.toList paths);

    startAt = "daily";
    compression = "auto,zstd";

    # A healthy run is otherwise completely silent: nixpkgs invokes borg with
    # no --stats/--list/--verbose, so the dashboard's log panels have nothing
    # to show between failures and "the backup ran but wrote nothing" is
    # invisible. --stats adds one summary block per archive (original/
    # compressed/deduplicated size, number of files) and prune's reports the
    # space it reclaimed. Deliberately not --list: that is one line per file,
    # which for the 469 G jellyfin tree would be the whole journal.
    extraCreateArgs = [ "--stats" ];
    extraPruneArgs = [ "--stats" ];

    environment.BORG_RSH = "ssh -i ${config.ogama.identity.sshKeyPath.pub}";
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
        paths = config.ogama.server.path.SSD_path;
        repo = config.ogama.server.path.backup.SSD_path;
      };

      "hdd-share-public-backup" = mkBasicJob {
        paths = config.ogama.server.path.hdd.share.public_HDD_path;
        repo = config.ogama.server.path.backup.hdd.share.public_HDD_path;
      };

      "hdd-app-immich-backup" = mkBasicJob {
        paths = config.ogama.server.path.hdd.app.immich;
        repo = config.ogama.server.path.backup.hdd.app.immich;
      };

      "hdd-app-jellyfin-backup" = mkBasicJob {
        paths = config.ogama.server.path.hdd.app.jellyfin;
        repo = config.ogama.server.path.backup.hdd.app.jellyfin;
      };

      "hdd-document-backup" = mkBasicJob {
        paths = config.ogama.server.path.hdd.document;
        repo = config.ogama.server.path.backup.hdd.document;
      };

      "hdd-photo-backup" = mkBasicJob {
        paths = config.ogama.server.path.hdd.photo;
        repo = config.ogama.server.path.backup.hdd.photo;
      };

      "hdd-photo-1-backup" = mkBasicJob {
        paths = config.ogama.server.path.hdd.photo_1;
        repo = config.ogama.server.path.backup.hdd.photo_1;
      };
    };

    repos = {

      # --------- LOCAL --------- #

      "ssd-backup" = {
        authorizedKeys = [ config.ogama.identity.sshPubkey ];
        path = config.ogama.server.path.backup.SSD_path;
      };

      "hdd-share-public-backup" = {
        authorizedKeys = [ config.ogama.identity.sshPubkey ];
        path = config.ogama.server.path.backup.hdd.share.public_HDD_path;
      };

      "hdd-app-immich-backup" = {
        authorizedKeys = [ config.ogama.identity.sshPubkey ];
        path = config.ogama.server.path.backup.hdd.app.immich;
      };

      "hdd-app-jellyfin-backup" = {
        authorizedKeys = [ config.ogama.identity.sshPubkey ];
        path = config.ogama.server.path.backup.hdd.app.jellyfin;
      };

      "hdd-document-backup" = {
        authorizedKeys = [ config.ogama.identity.sshPubkey ];
        path = config.ogama.server.path.backup.hdd.document;
      };

      "hdd-photo-backup" = {
        authorizedKeys = [ config.ogama.identity.sshPubkey ];
        path = config.ogama.server.path.backup.hdd.photo;
      };

      "hdd-photo-1-backup" = {
        authorizedKeys = [ config.ogama.identity.sshPubkey ];
        path = config.ogama.server.path.backup.hdd.photo_1;
      };
      # --------- REMOTE --------- #
      "laptop-document-backup" = {
        authorizedKeys = [ config.ogama.identity.sshPubkey ];
        path = config.ogama.server.path.backup.laptop.document;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${config.ogama.server.path.backup.SSD_path}                   0755 borg users -"

    "d ${config.ogama.server.path.backup.HDD_path}                   0755 borg users -"
    "d ${config.ogama.server.path.backup.hdd.document}              0755 borg users -"
    "d ${config.ogama.server.path.backup.hdd.photo}                 0755 borg users -"
    "d ${config.ogama.server.path.backup.hdd.photo_1}               0755 borg users -"
    "d ${config.ogama.server.path.backup.hdd.share.path}             0755 borg users -"
    "d ${config.ogama.server.path.backup.hdd.share.public_HDD_path}  0755 borg users -"
    "d ${config.ogama.server.path.backup.HDD_app}                    0755 borg users -"
    "d ${config.ogama.server.path.backup.hdd.app.immich}             0755 borg users -"
    "d ${config.ogama.server.path.backup.hdd.app.jellyfin}           0755 borg users -"

    "d ${config.ogama.server.path.backup.laptop.path}                0755 borg users -"
    "d ${config.ogama.server.path.backup.laptop.document}            0755 borg users -"
  ];
  users.users.borg = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILaKjKo1kaGVYdA5U6kvrjhDj1T3tp04CmiZE3YmA7id ogama@nixos"
    ];
  };

}
