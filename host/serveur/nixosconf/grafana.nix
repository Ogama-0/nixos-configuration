{ cfg, config, ... }:

{

  # -------------------- Grafana -------------------- #

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

      analytics.reporting_enabled = false;
    };

    provision = {
      enable = true;

      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:${toString config.services.prometheus.port}";
        }

        {
          name = "Loki";
          type = "loki";
          access = "proxy";
          url = "http://127.0.0.1:${
              toString
              config.services.loki.configuration.server.http_listen_port
            }";
        }
      ];
    };
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

  services.prometheus = {
    enable = true;

    port = 9001;

    exporters.node = {
      enable = true;
      port = 9002;
      enabledCollectors = [ "systemd" ];
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
        job_name = "loki";

        static_configs = [{ targets = [ "127.0.0.1:3030" ]; }];
      }

      {
        job_name = "promtail";

        static_configs = [{ targets = [ "127.0.0.1:3031" ]; }];
      }

    ];
  };

  # -------------------- Grafana -------------------- #
  ############################
  ## PROMTAIL
  ############################
  services.promtail = {
    enable = true;

    configuration = {

      server = {
        http_listen_port = 3031;
        grpc_listen_port = 0;
      };

      clients = [{ url = "http://127.0.0.1:3030/loki/api/v1/push"; }];

      positions = { filename = "/var/lib/promtail/positions.yaml"; };
      services.promtail.configuration.scrape_configs = [

        # =========================
        # SYSTEMD JOURNAL
        # =========================

        {
          job_name = "journal";

          journal = { max_age = "12h"; };

          relabel_configs = [
            {
              source_labels = [ "__journal__systemd_unit" ];
              target_label = "unit";
            }
            {
              source_labels = [ "__journal__hostname" ];
              target_label = "host";
            }
            {
              source_labels = [ "__journal_priority_keyword" ];
              target_label = "level";
            }
          ];
        }

        # =========================
        # DOCKER LOGS
        # =========================

        {
          job_name = "docker";

          static_configs = [{
            targets = [ "localhost" ];

            labels = {
              job = "docker";
              __path__ = "/var/lib/docker/containers/*/*.log";
            };
          }];
        }

        # =========================
        # SYSLOG FILES
        # =========================

        {
          job_name = "syslog";

          static_configs = [{
            targets = [ "localhost" ];

            labels = {
              job = "syslog";
              __path__ = "/var/log/*.log";
            };
          }];
        }

      ];
    };
  };
  systemd.tmpfiles.rules = [ "d /var/lib/promtail 0755 promtail promtail -" ];
  # -------------------- ngnix -------------------- #
  services.nginx.virtualHosts = cfg.ngnix.mkVhost {
    subdomain = "grafana";
    proxyPass = "http://127.0.0.1:3000";
    https = false;
  };

}
