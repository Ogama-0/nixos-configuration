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
