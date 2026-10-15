{ cfg, config, ... }:

let host = "status.tail.${cfg.server.domain}";
in {
  # Gatus actively probes each service and exposes the result as plain,
  # unauthenticated JSON at /api/v1/endpoints/statuses. This is what the
  # Quickshell desktop widget reads: a boolean "is it answering" costs one
  # unauthenticated GET, where the same question asked of Grafana needs a
  # provisioned token and a range query. It also catches a wedged service,
  # which systemd's unit state (what node-exporter's "systemd" collector
  # reports) cannot.
  services.gatus = {
    enable = true;

    # No openFirewall: Gatus binds loopback and is only reached through
    # Caddy, which is itself only resolvable on the tailnet.

    settings = {
      web = {
        address = "127.0.0.1";
        # Not Gatus's own default of 8080 — services.qbittorrent.webuiPort
        # already holds that port on this host.
        port = 8085;
      };

      # The default store is in-memory, so every rebuild would blank the
      # rolling `results` history the widget draws its sparklines from.
      # The unit runs with DynamicUser + StateDirectory=gatus, so
      # /var/lib/gatus is the writable path available to it.
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
      };

      # Every endpoint declares exactly two conditions, in this order:
      # status first, response time second. The widget reads
      # `conditionResults` positionally to tell three states apart —
      # status failed => down, status ok but time failed => degraded,
      # both ok => up. Collapsing them into one condition, or swapping
      # the order, silently destroys the middle tier.
      #
      # `key` is "{group}_{name}" lowercased with spaces/dots/slashes/
      # underscores turned into "-" (gatus config/key/key.go). It is the
      # join key between a row, its Prometheus metrics and its widget
      # label, so renaming a group or an endpoint is an API break.
      #
      # Probing goes through the public hostname wherever a vhost exists:
      # the question is "can I use this", and that path includes DNS,
      # Tailscale, Caddy and the backend. If Caddy dies every row goes red
      # at once, which is correct — the Caddy row says why. Immich ML and
      # Samba have no vhost and are probed directly.
      endpoints = [
        {
          name = "Jellyfin";
          group = "media";
          # "/" answers 302 (redirect to /web/), which would fail
          # [STATUS] == 200 even on a perfectly healthy Jellyfin.
          url = "http://jellyfin.tail.${cfg.server.domain}/health";
          interval = "15s";
          conditions = [ "[STATUS] == 200" "[RESPONSE_TIME] < 300" ];
        }
        {
          name = "Immich";
          group = "media";
          url = "http://immich.tail.${cfg.server.domain}";
          interval = "15s";
          conditions = [ "[STATUS] == 200" "[RESPONSE_TIME] < 300" ];
        }
        {
          # services.immich.machine-learning exposes no port option; 3003
          # was read off the running system (ss -ltnp) and /ping answers
          # 200 "pong" there.
          name = "Immich ML";
          group = "media";
          url = "http://127.0.0.1:3003/ping";
          interval = "15s";
          conditions = [ "[STATUS] == 200" "[RESPONSE_TIME] < 300" ];
        }
        {
          name = "Samba";
          group = "files";
          url = "tcp://127.0.0.1:445";
          interval = "15s";
          # A TCP probe has no status code, so [CONNECTED] takes the first
          # slot the widget expects the status condition in.
          conditions = [ "[CONNECTED] == true" "[RESPONSE_TIME] < 300" ];
        }
        {
          name = "qBittorrent";
          group = "files";
          url = "http://qbittorrent.tail.${cfg.server.domain}";
          interval = "15s";
          conditions = [ "[STATUS] == 200" "[RESPONSE_TIME] < 300" ];
        }
        {
          # Caddy's own admin API, which also serves the metrics Prometheus
          # scrapes. Probed on loopback by necessity: proxying Caddy
          # through Caddy would only ever prove Caddy is up.
          name = "Caddy";
          group = "web";
          url = "http://127.0.0.1:2019/metrics";
          interval = "15s";
          conditions = [ "[STATUS] == 200" "[RESPONSE_TIME] < 300" ];
        }
        {
          name = "Grafana";
          group = "web";
          url = "http://grafana.tail.${cfg.server.domain}/api/health";
          interval = "15s";
          conditions = [ "[STATUS] == 200" "[RESPONSE_TIME] < 300" ];
        }
        {
          # Joplin Server runs in docker (see joplin-server.nix). /api/ping
          # is its health endpoint and answers 200 {"status":"ok"}; "/"
          # redirects to /login, which would fail [STATUS] == 200.
          name = "Joplin";
          group = "dev";
          url = "http://joplin.tail.${cfg.server.domain}/api/ping";
          interval = "15s";
          conditions = [ "[STATUS] == 200" "[RESPONSE_TIME] < 300" ];
        }
        {
          name = "Wakapi";
          group = "dev";
          url = "http://wakapi.tail.${cfg.server.domain}";
          interval = "15s";
          conditions = [ "[STATUS] == 200" "[RESPONSE_TIME] < 300" ];
        }
        {
          # Rustical answers 200 "Pong!" on /ping with no auth. "/" is the web
          # frontend, which redirects to /frontend/login.
          #
          # Probed on the tail name, not the public https:// one, matching
          # what Jellyfin does with its two names. The public vhost depends on
          # the ISP's IPv6 prefix still matching the portal's AAAA record, so
          # probing it would make this row red for a DNS problem outside the
          # service. The cost is that a failed certificate renewal does not
          # show up here — for that, `journalctl -u caddy | grep -i acme`.
          name = "Rustical";
          group = "calendar";
          url = "http://rustical.tail.${cfg.server.domain}/ping";
          interval = "15s";
          conditions = [ "[STATUS] == 200" "[RESPONSE_TIME] < 300" ];
        }
        {
          # 401 is the *healthy* answer here: calendar-syncer puts HTTP basic
          # auth in front of every route including "/", and the probe sends no
          # credentials. Expecting 200 would leave a correctly secured service
          # looking permanently down; 401 still fails on a dead or wedged one,
          # which is what the row is for.
          name = "Calsync";
          group = "calendar";
          url = "http://calsync.tail.${cfg.server.domain}";
          interval = "15s";
          conditions = [ "[STATUS] == 401" "[RESPONSE_TIME] < 300" ];
        }
        {
          # Probes the CORS proxy, not the static site: Caddy serves the site
          # from the nix store and would answer 200 with the proxy unit dead,
          # and the proxy is the half that can actually break. handle_path
          # strips /proxy, so this lands on the proxy's own /health.
          name = "Calino";
          group = "calendar";
          url = "http://calino.tail.${cfg.server.domain}/proxy/health";
          interval = "15s";
          conditions = [ "[STATUS] == 200" "[RESPONSE_TIME] < 300" ];
        }
      ];

      # No `security` block on purpose: the response carries only service
      # names and response times, the probes need no secrets, and the
      # vhost below is tailnet-only. See also the comment in grafana.nix
      # on the path-restricted Prometheus vhost.
    };
  };

  # 15s probes against a widget that polls every 10s: each result is seen
  # roughly once. Probing faster multiplies load on the probed services
  # for data that has not changed.

  services.caddy.virtualHosts."http://${host}" = {
    extraConfig = ''
      reverse_proxy http://127.0.0.1:${
        toString config.services.gatus.settings.web.port
      }
    '';
  };
}
