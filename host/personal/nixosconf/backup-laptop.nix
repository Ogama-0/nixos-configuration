{ cfg, ... }:
let document_path = "${cfg.home_path}/document";
in {
  services.borgbackup = {

    jobs = {
      "document_perso" = {
        paths = document_path;
        patterns = [
          "- ${document_path}/.Trash-1000" # don't backup trash
          "- ${document_path}/lost+found"
        ];
        startAt = "daily";
        compression = "auto,zstd";
        environment.BORG_RSH = "ssh -i ${cfg.ssh.path.pub}";
        repo = "borg@ogamaservhost:/mnt/backup/pc-perso-backup/document";
        encryption.mode = "none";
        prune.keep = {
          within = "1d";
          daily = 7;
          weekly = 4;
          monthly = 2;
        };
      };
    };
  };
}
