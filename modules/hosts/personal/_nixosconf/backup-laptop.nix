{ config, ... }:
let document_path = "${config.ogama.identity.homePath}/document";
in {
  services.borgbackup = {

    jobs = {
      "laptop-document-backup" = {
        paths = document_path;
        patterns = [
          "- ${document_path}/.Trash-1000" # don't backup trash
          "- ${document_path}/lost+found"
        ];
        startAt = "daily";
        compression = "auto,zstd";
        environment.BORG_RSH = "ssh -i ${config.ogama.identity.sshKeyPath.priv}";
        repo = "borg@ogamaservhost:${config.ogama.server.path.backup.laptop.document}";
        encryption.mode = "none";
        prune.keep = {
          within = "1d";
          daily = 7;
          weekly = 4;
          monthly = 2;
        };
        # extraArgs = [ "--debug" "--verbose" "--show-rc" "--log-json" ];
        # environment = {
        #   BORG_LOGGING_CONF = "debug";
        #   BORG_SHOW_RC = "1";
        # };
      };
    };
  };
}
