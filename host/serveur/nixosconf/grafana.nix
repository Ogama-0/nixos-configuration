{ cfg, config, ... }:

{

  # -------------------- Grafana -------------------- #

  sops.secrets."grafana_secret_key" = {
    sopsFile = ../../../sops/oserv.yaml;
    owner = "grafana";
  };

  services.grafana = {
    enable = true;

    settings = {
      server = {
        protocol = "http";
        addr = "127.0.0.1";
        http_addr = "127.0.0.1";
        http_port = 3000;
        enforce_domain = true;
        enable_gzip = true;
        domain = "grafana.tail.${cfg.server.domain}";
      };

      security.secret_key =
        "$__file{${config.sops.secrets."grafana_secret_key".path}}";

      analytics.reporting_enabled = false;
    };

    provision = {
      enable = true;

      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          uid = "prometheus";
          access = "proxy";
          isDefault = true;
          url = "http://127.0.0.1:${toString config.services.prometheus.port}";
        }

        {
          name = "Loki";
          type = "loki";
          uid = "loki";
          access = "proxy";
          url = "http://127.0.0.1:${
              toString
              config.services.loki.configuration.server.http_listen_port
            }";
        }
      ];

      dashboards.settings.providers = [{
        name = "oserv";
        options.path = "/etc/grafana-dashboards";
      }];
    };
  };

  environment.etc."grafana-dashboards/oserv-services.json".source =
    ./grafana-dashboard.json;

  services.caddy.virtualHosts."http://grafana.tail.${cfg.server.domain}" = {
    extraConfig = ''
      reverse_proxy http://127.0.0.1:3000
    '';
  };

  # Read-only window onto Prometheus for the Quickshell status widget
  # (per-service CPU/RAM, host load/memory/disk). Deliberately NOT a bare
  # reverse_proxy: Prometheus's HTTP API is unauthenticated, so proxying
  # all of it would hand anyone on the tailnet /api/v1/status/config,
  # /flags, /targets and the admin/TSDB endpoints. Only the single
  # instant-query path the widget uses is forwarded; everything else 404s.
  # That restriction is the security control here — it must not be
  # loosened to a bare proxy for convenience. Metric *data* does remain
  # readable tailnet-wide, which is the accepted tradeoff.
  services.caddy.virtualHosts."http://metrics.tail.${cfg.server.domain}" = {
    extraConfig = ''
      handle /api/v1/query* {
          reverse_proxy http://127.0.0.1:${
            toString config.services.prometheus.port
          }
      }
      handle {
          respond 404
      }
    '';
  };

  # -------------------- Loki -------------------- #

  services.loki = {
    enable = true;

    configuration = {

      auth_enabled = false;

      server = { http_listen_port = 3030; };

      common = {
        path_prefix = "/var/lib/loki";

        replication_factor = 1;

        ring = {
          instance_addr = "127.0.0.1";
          kvstore.store = "inmemory";
        };

        storage = {
          filesystem = {
            chunks_directory = "/var/lib/loki/chunks";
            rules_directory = "/var/lib/loki/rules";
          };
        };
      };

      schema_config = {
        configs = [{
          from = "2024-01-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";

          index = {
            prefix = "index_";
            period = "24h";
          };
        }];
      };

      storage_config = {
        filesystem = { directory = "/var/lib/loki/chunks"; };
      };
    };
  };

  # -------------------- Prometheus -------------------- #

  services.prometheus = {
    enable = true;

    port = 9001;

    exporters.node = {
      enable = true;
      port = 9002;
      enabledCollectors = [ "systemd" ];
    };

    # Per-service CPU/memory — node exporter's own "systemd" collector
    # only reports unit state, not resource usage. process-exporter has
    # no cgroup matcher (its "Cgroups" field is a naming template
    # variable only), so grouping is by comm/cmdline instead:
    # - jellyfin: single "jellyfin" process
    # - immich-server: "immich" (main) + "immich-api" (worker) processes
    # - immich-machine-learning: gunicorn/uvicorn workers running
    #   immich_ml.main:app, identified via cmdline (comm is just
    #   "python3.13", too generic to match on its own)
    # - samba-smbd: "smbd" main + notifyd/cleanupd children
    # - qbittorrent: comm is useless here — the kernel truncates it to 15
    #   chars and the Nix wrapper prefixes a dot, giving
    #   ".qbittorrent-no", so the old comm = [ "qbittorrent-nox" ] matched
    #   nothing and this group was silently absent from Prometheus.
    #   Matched on cmdline instead.
    # - caddy, grafana: plain single "caddy" / "grafana" comms, added for
    #   the status widget, which shows CPU/RAM on all eight of its rows.
    #   comm matching is exact, so grafana's "gpx_grafana_ela" plugin
    #   helper process is correctly left out of that group.
    exporters.process = {
      enable = true;
      settings.process_names = [
        {
          name = "jellyfin";
          comm = [ "jellyfin" ];
        }
        {
          name = "immich-server";
          comm = [ "immich" "immich-api" ];
        }
        {
          name = "immich-machine-learning";
          cmdline = [ "immich_ml\\.main:app" ];
        }
        {
          name = "samba-smbd";
          comm = [ "smbd" ];
        }
        {
          name = "wakapi";
          comm = [ "wakapi" ];
        }
        {
          name = "qbittorrent";
          cmdline = [ "qbittorrent-nox" ];
        }
        {
          name = "caddy";
          comm = [ "caddy" ];
        }
        {
          name = "grafana";
          comm = [ "grafana" ];
        }
      ];
    };

    scrapeConfigs = [

      {
        job_name = "prometheus";

        static_configs = [{ targets = [ "127.0.0.1:9001" ]; }];
      }

      {
        job_name = "node";

        static_configs = [{ targets = [ "127.0.0.1:9002" ]; }];
      }

      {
        job_name = "process";

        # The status widget asks for rate(...[1m]), and rate() needs two
        # samples inside its window. At the global 1m scrape_interval a 1m
        # window holds at most one, so that query returned no series at
        # all. 15s puts four in the window. Only this job is sped up:
        # process-exporter is ~16 series, where giving node-exporter the
        # same treatment would quadruple the bulk of the TSDB for gauges
        # an instant query reads fine at 1m.
        scrape_interval = "15s";

        static_configs = [{ targets = [ "127.0.0.1:9256" ]; }];
      }

      {
        job_name = "loki";

        static_configs = [{ targets = [ "127.0.0.1:3030" ]; }];
      }

      {
        job_name = "caddy";

        static_configs = [{ targets = [ "127.0.0.1:2019" ]; }];
      }

    ];
  };

  # -------------------- Alloy -------------------- #
  # promtail reached end-of-life and was removed from nixpkgs; Alloy is
  # Grafana's officially recommended replacement. Config lives in
  # ./alloy-config.alloy (the Alloy/River config language, not Nix).

  services.alloy.enable = true;
  environment.etc."alloy/config.alloy".source = ./alloy-config.alloy;
}
