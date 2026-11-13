{ config, pkgs, lib, ... }:

let
  # node-exporter's textfile collector reads every *.prom here. The exporter
  # runs as a DynamicUser and only ever reads; 0755/0644 is enough for that,
  # and the collector unit below is the only writer.
  textfileDir = "/var/lib/prometheus-node-exporter-text-files";

  # borg insists on a cache/config directory even for a manifest read. Passed
  # to the script as an input rather than baked into it, both so it cannot
  # drift from the StateDirectory below and so the script stays runnable by
  # hand against a scratch repository.
  borgBaseDir = "/var/lib/borg-metrics";

  # Derived from the repositories themselves rather than listed a second time,
  # so a new entry in backup-server.nix's `repos` reaches the dashboard without
  # a matching edit here. laptop-document-backup is covered too: it is pushed
  # from `personal` over ssh, but the repository lives on this host, so it is
  # read exactly like the local ones.
  repoListFile = pkgs.writeText "backup-metrics-repos" (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: repo: "${name}\t${repo.path}") config.services.borgbackup.repos
    )
    + "\n"
  );

  collector = pkgs.writeShellApplication {
    name = "backup-metrics";
    runtimeInputs = with pkgs; [
      borgbackup
      jq
      coreutils
      findutils
      gawk
    ];
    text = builtins.readFile ./backup-metrics.sh;
  };
in
{
  # The textfile collector ships enabled in node-exporter but is inert without
  # a directory. The flag lives here rather than in grafana.nix so it cannot
  # drift away from the unit that fills that directory.
  services.prometheus.exporters.node.extraFlags = [
    "--collector.textfile.directory=${textfileDir}"
  ];

  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 root root -"
  ];

  systemd.services.backup-metrics = {
    description = "Collect borg and Time Machine metrics for node-exporter";

    environment = {
      BACKUP_REPOS_FILE = "${repoListFile}";
      TIMEMACHINE_ROOT = config.ogama.server.path.hdd.share.Apple_save_HDD_path;
      TEXTFILE_DIR = textfileDir;
      BORG_BASE_DIR = borgBaseDir;
    };

    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe collector;

      # Runs as root: the repositories are mode 0700 root-owned inside, so
      # anything less reads every repository as empty.
      StateDirectory = baseNameOf borgBaseDir;

      # Every sparsebundle is walked in full and every repository is du'd.
      # That is pure I/O, and it runs alongside the backup jobs and the Samba
      # clients using the same disks — so it yields to both.
      Nice = 19;
      IOSchedulingClass = "idle";

      # A held repository lock or a stalled disk must not wedge the timer.
      TimeoutStartSec = "10m";
    };
  };

  systemd.timers.backup-metrics = {
    description = "Refresh borg and Time Machine metrics";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Borg runs daily and Time Machine hourly, so 15m is well inside both.
      # The dashboard's freshness panel goes amber at 30m.
      OnBootSec = "5m";
      OnUnitActiveSec = "15m";
      Persistent = true;
    };
  };
}
