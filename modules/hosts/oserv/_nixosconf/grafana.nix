{
  config,
  pkgs,
  ...
}:

let
  # The URLs probed for La Scène intérieure, innermost first. They live here
  # because three places have to agree on them to the character: the blackbox
  # job's targets, the `instance` labels that come out of it, and the panels
  # that select on those labels. The port comes from the service's own option
  # rather than a repeated 3500 (see modules/features/server/la-scene-interieure.nix,
  # which moves it off Grafana's 3000).
  lsiUpstream = "127.0.0.1:${toString config.services.laSceneInterieure.port}";
  lsiProbeAppLocal = "http://${lsiUpstream}/";

  # Not the home page: the two outages of 12 November 2026 both left "/"
  # answering 200 while every page that reads the contents was dead (500, then
  # SIGSEGV). /solo is the cheapest route that touches the database and loads
  # the image code, and it answers 200 without a session.
  lsiProbeContenus = "http://${lsiUpstream}/solo";

  # The public names, so the probe crosses Milo and TLS exactly as a visitor
  # does. app.lsi is the application; lsi is the pre-rendered vitrine, which has
  # no process and no unit, so a probe is the only thing that can say it is up.
  lsiProbeApp = "https://app.lsi.${config.ogama.server.domain}/";
  lsiProbeVitrine = "https://lsi.${config.ogama.server.domain}/";
in

{

  # -------------------- Grafana -------------------- #

  sops.secrets."grafana_secret_key" = {
    sopsFile = ../../../../sops/oserv.yaml;
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
        domain = "grafana.tail.${config.ogama.server.domain}";
      };

      security.secret_key = "$__file{${config.sops.secrets."grafana_secret_key".path}}";

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
          url = "http://127.0.0.1:${toString config.services.loki.configuration.server.http_listen_port}";
        }
      ];

      dashboards.settings.providers = [
        {
          name = "oserv";
          options.path = "/etc/grafana-dashboards";
        }
      ];
    };
  };

  # @HDD_PATH@ keeps the dashboard's HDD panel following config.ogama.server.path.HDD_path
  # rather than a hardcoded mountpoint string that silently goes stale the
  # next time that path is renamed (as it was, from /mnt/hdd-tmp).
  environment.etc."grafana-dashboards/oserv-services.json".text =
    builtins.replaceStrings [ "@HDD_PATH@" ] [ config.ogama.server.path.HDD_path ]
      (builtins.readFile ./grafana-dashboard.json);

  # La Scène intérieure gets a dashboard of its own rather than two more rows on
  # the one above: it is the only service here with a public website in front of
  # it, so "is it up" has four different answers (unit, local port, local Caddy,
  # public name) that are worth seeing side by side. The host-wide dashboard
  # stays a per-service UP/DOWN grid.
  #
  # The probe URLs are substituted for the same reason @HDD_PATH@ is: they are
  # the `instance` label the panels select on, so a hardcoded domain would make
  # every website panel go quietly empty the day config.ogama.server.domain changes. They must
  # match the targets of the blackbox-lsi job below character for character —
  # trailing slash included.
  environment.etc."grafana-dashboards/la-scene-interieure.json".text =
    builtins.replaceStrings
      [
        "@UPSTREAM@"
        "@APP_LOCAL_URL@"
        "@CONTENUS_URL@"
        "@APP_URL@"
        "@VITRINE_URL@"
      ]
      [
        lsiUpstream
        lsiProbeAppLocal
        lsiProbeContenus
        lsiProbeApp
        lsiProbeVitrine
      ]
      (builtins.readFile ./grafana-dashboard-lsi.json);

  services.caddy.virtualHosts."http://grafana.tail.${config.ogama.server.domain}" = {
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
  services.caddy.virtualHosts."http://metrics.tail.${config.ogama.server.domain}" = {
    extraConfig = ''
      handle /api/v1/query* {
          reverse_proxy http://127.0.0.1:${toString config.services.prometheus.port}
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

      server = {
        http_listen_port = 3030;
      };

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
        configs = [
          {
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";

            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
      };

      storage_config = {
        filesystem = {
          directory = "/var/lib/loki/chunks";
        };
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
    # - joplin: runs in docker, but its processes are ordinary host
    #   processes as far as /proc is concerned, so process-exporter sees
    #   them normally. comm is "node", far too generic, hence the cmdline
    #   match on the app entrypoint. Only the app is grouped, not its
    #   postgres sidecar: the container's postgres is indistinguishable by
    #   comm from the host postgres that Immich runs, and lumping them
    #   together would quietly corrupt Immich's numbers.
    # - rustical, calendar_syncer: single-process Rust binaries, plain comm
    #   matches. calendar-syncer's matcher name uses a dash where its comm
    #   uses an underscore (the binary is calendar_syncer) — the two are
    #   independent, and the dashed form is what the widget's promGroup
    #   expects.
    # - calino-proxy: the Calino *site* is static files served by Caddy and so
    #   has no process of its own; only its CORS proxy does, and that is a
    #   node process whose comm is "node", hence the cmdline match.
    exporters.process = {
      enable = true;
      settings.process_names = [
        {
          name = "jellyfin";
          comm = [ "jellyfin" ];
        }
        {
          name = "immich-server";
          comm = [
            "immich"
            "immich-api"
          ];
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
        {
          name = "joplin";
          cmdline = [ "packages/server/dist/app\\.js" ];
        }
        {
          name = "rustical";
          comm = [ "rustical" ];
        }
        {
          # "calendar_syncer" is exactly 15 characters, so the kernel's comm
          # truncation leaves it intact — one more character upstream and this
          # would have to move to cmdline.
          name = "calendar-syncer";
          comm = [ "calendar_syncer" ];
        }
        {
          # The static site is served by Caddy itself and has no process; this
          # is the CORS proxy, whose comm is just "node".
          name = "calino-proxy";
          cmdline = [ "share/calino/proxy/server\\.mjs" ];
        }
        {
          # Another "node" comm (la-scene-interieure.nix), matched on its
          # entrypoint. The unit's cmdline is literally "node production.ts":
          # the wrapper in the store cd's into its own share/ before exec'ing
          # node, so no path appears in argv at all and there is nothing more
          # specific to anchor on.
          # It does not collide with the two node matchers above, which match
          # their own distinct entrypoint filenames.
          name = "la-scene-interieure";
          cmdline = [ "production\\.ts" ];
        }
      ];
    };

    # Blackbox, for the one service here that has a website in front of it.
    # Everything else on this host is reachable over the tailnet only, where "is
    # the unit active" is the whole answer. La Scène intérieure answers the
    # public internet through an external relay, and its vitrine is pre-rendered
    # files with no process at all — probing is the only way to see either.
    exporters.blackbox = {
      enable = true;
      port = 9115;
      configFile = (pkgs.formats.yaml { }).generate "blackbox.yml" {
        modules.http_2xx = {
          prober = "http";
          timeout = "10s";
          http = {
            # Redirects are followed on purpose: the app sends visitors without
            # a session to the login page with a 303, and that is a healthy
            # answer. What this checks is that the route renders at all — both
            # failures of 12 November 2026 happened while loading the page's
            # own module, well before any redirect.
            follow_redirects = true;
          };
        };
      };
    };

    scrapeConfigs = [

      {
        job_name = "prometheus";

        static_configs = [ { targets = [ "127.0.0.1:9001" ]; } ];
      }

      {
        job_name = "node";

        static_configs = [ { targets = [ "127.0.0.1:9002" ]; } ];
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

        static_configs = [ { targets = [ "127.0.0.1:9256" ]; } ];
      }

      {
        job_name = "loki";

        static_configs = [ { targets = [ "127.0.0.1:3030" ]; } ];
      }

      {
        job_name = "caddy";

        static_configs = [ { targets = [ "127.0.0.1:2019" ]; } ];
      }

      {
        job_name = "blackbox-lsi";

        # The exporter is *asked* to probe a URL, so what gets scraped is the
        # exporter and the URL travels as ?target=. The three relabel rules
        # below are the standard dance for that: put the configured target in
        # the query parameter, keep it as the series' `instance` (which is what
        # the dashboard selects on, hence the shared definitions at the top of
        # this file), then point the scrape itself at the exporter.
        metrics_path = "/probe";
        params.module = [ "http_2xx" ];

        # Every probe is a real request to the real site, so once a minute:
        # enough to catch an outage within the span of a coffee, cheap enough
        # not to matter, and it keeps the vitrine's figures honest.
        scrape_interval = "60s";

        static_configs = [
          {
            targets = [
              lsiProbeAppLocal
              lsiProbeContenus
              lsiProbeApp
              lsiProbeVitrine
            ];
          }
        ];

        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:${toString config.services.prometheus.exporters.blackbox.port}";
          }
        ];
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
