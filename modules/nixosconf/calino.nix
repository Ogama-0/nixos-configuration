{ cfg, lib, lpkgs, pkgs, ... }:

let
  host = "calino.tail.${cfg.server.domain}";
  origin = "http://${host}";
  proxyPort = 8081;

  # Hosts the CORS proxy may be pointed at. This is the proxy's only real
  # security control — it will otherwise relay to anything the server can
  # reach — so it is a short allowlist of the ICS feeds we actually
  # subscribe to, not a wildcard. zeus.ionis-it.com is the EPITA calendar.
  # Private/link-local addresses are refused unconditionally by the proxy
  # itself, allowlist or not.
  allowedTargets = [ "zeus.ionis-it.com" ];
in {
  # Calino (calino.io) is a CalDAV client that runs entirely in the browser:
  # the vhost below is a static site, and all calendar traffic goes from the
  # browser straight to rustical.nix (which is why rustical's vhost carries
  # CORS headers for this exact origin).
  #
  # The site is served over plain HTTP like everything else on the tailnet,
  # which Calino refuses by default for DAV connections; the package is built
  # with CALINO_SELF_HOSTED=true to permit it (see pkgs/calino.nix).

  # Separate from the site: ICS/webcal feeds are third-party servers that send
  # no CORS headers, so the browser cannot fetch them directly. Upstream's
  # answer is this tiny node relay, which Calino calls at /proxy/*.
  systemd.services.calino-proxy = {
    description = "Calino CORS proxy for webcal feeds";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      PORT = toString proxyPort;
      ALLOWED_ORIGINS = origin;
      ALLOWED_TARGETS = lib.concatStringsSep "," allowedTargets;
    };

    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.nodejs_22} ${lpkgs.calino}/share/calino/proxy/server.mjs";
      DynamicUser = true;
      Restart = "on-failure";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      # It holds one request body at a time (capped at 10 MiB upstream) and
      # keeps no state; anything past this is a leak, not load.
      MemoryMax = "128M";
    };
  };

  services.caddy.virtualHosts."http://${host}" = {
    extraConfig = ''
      encode zstd gzip

      handle_path /proxy/* {
          # The proxy rejects requests whose Origin is not in ALLOWED_ORIGINS,
          # and some clients (and every curl) send no Origin at all. Filling
          # it in here is safe because this route is only reachable through
          # this vhost, which is the allowed origin.
          @no_origin not header Origin *
          request_header @no_origin Origin ${origin}
          reverse_proxy http://127.0.0.1:${toString proxyPort}
      }

      handle {
          root * ${lpkgs.calino}/share/calino/web
          # Single-page app: unknown paths are client-side routes, so they
          # have to fall back to index.html rather than 404.
          try_files {path} /index.html
          file_server

          header {
              X-Frame-Options "SAMEORIGIN"
              X-Content-Type-Options "nosniff"
              Referrer-Policy "strict-origin-when-cross-origin"
              Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()"
              -Server
          }

          # Vite fingerprints everything under /assets, so these are safe to
          # cache forever; index.html deliberately is not.
          @assets path /assets/*
          header @assets Cache-Control "public, immutable"
      }
    '';
  };
}
