{ config, ... }:
let
  document_path = "${config.ogama.identity.homePath}/Documents";
in
{
  # The borg job runs as root, so it does not read ~ogama/.ssh/known_hosts.
  # Declared here rather than in modules/features/core/ssh.nix, whose
  # knownHosts block is gated behind ogama.core.ssh.enable — off on this
  # laptop. Without it the job dies with "Host key verification failed".
  programs.ssh.knownHosts.ogamaservhost.publicKey = config.ogama.server.sshHostKey;

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
