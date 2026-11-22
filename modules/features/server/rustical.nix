{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.rustical.enable =
        lib.mkEnableOption "the CalDAV server behind the calendar stack";
    };
in
{
  flake.featureModules.nixos.rustical =
    {
      lib,
      config,
      inputs,
      upkgs,
      ...
    }:
    {
      # The extra entries instruct the module system and cannot live inside
      # mkIf, so they apply whether or not the feature is enabled. What they
      # pull in only declares options and gates its own behaviour.
      imports = [
        sharedOptions
        "${inputs.nixpkgs-unstable}/nixos/modules/services/web-apps/rustical.nix"
      ];

      disabledModules = [ "services/web-apps/rustical.nix" ];

      config = lib.mkIf config.ogama.server.rustical.enable (
        let
          # The 0.16 line from nixpkgs-unstable, not the 0.12.15 in stable. Both
          # halves have to come from unstable together: 0.13 renamed
          # `http.host`/`http.port` to a single `http.bind` and moved the server
          # behind a `serve` subcommand, so the *stable* module cannot drive a 0.16
          # binary — its ExecStart has no `serve`, and it writes config.toml keys the
          # new binary rejects. Hence the disabledModules/imports pair below.
          #
          # Unpinned on purpose, so the version tracks the nixpkgs-unstable input
          # rather than a hash pinned in this file.

          # 0.16's own default here is a UNIX socket at /run/rustical/sock, in a
          # RuntimeDirectory owned by the unit's DynamicUser with mode 0750. Caddy
          # runs as its own `caddy` user and is not in that group, so it cannot open
          # the socket; TCP on loopback keeps the vhosts (and the Gatus probe)
          # working without poking holes in either unit.
          bind = "127.0.0.1:4000";

          # Three names on purpose, for three different jobs:
          #
          # - ipv6Host's AAAA points straight at oserv, so Caddy can win ACME
          #   for it directly over IPv6 regardless of how publicHost itself
          #   resolves. The frontend needs *some* name with a real cert:
          #   rustical builds its session cookie with `.with_secure(true)`
          #   hardcoded in src/app.rs (still so in 0.16.0), with no config
          #   option, so over plain HTTP the browser drops the cookie and the
          #   login silently never sticks — no server-side error, the form
          #   just comes back. Minting an app token no longer *requires* the
          #   browser (0.16 added `rustical principals app-token create`),
          #   but browsing calendars and revoking tokens still happen there.
          #
          # - publicHost is the bare public name. Its AAAA now also points
          #   directly at oserv (its A still goes through the friend's VPS,
          #   which re-dials oserv), so it gets its own vhost/cert too —
          #   same split as opencloud.nix/immich.nix/jellyfin.nix. Both
          #   vhosts force the Host header to publicHost via `proxy` below,
          #   so the frontend only ever sees the one canonical name.
          #
          # - tailHost stays plain HTTP like the rest of the tailnet. It is
          #   what IPv4-only clients use, and CalDAV does not care: it
          #   authenticates with HTTP Basic and keeps no cookies, so only the
          #   web frontend is affected by the lack of TLS.
          ipv6Host = "rustical.${config.ogama.server.ipv6Host}";
          publicHost = "rustical.${config.ogama.server.domain}";
          tailHost = "rustical.tail.${config.ogama.server.domain}";

          # The browser origin Calino is served from. Rustical has to hand it CORS
          # headers explicitly, because Calino talks CalDAV from the page itself.
          calinoOrigin = "http://calino.tail.${config.ogama.server.domain}";

          # Shared by both vhosts so Calino works whichever name it is pointed at.
          # Kept as one string rather than duplicated: the preflight method list is
          # the sort of thing that gets edited once and forgotten in the other copy.
          #
          # Without Access-Control-Expose-Headers the browser can read the response
          # but not ETag/DAV/Allow, and a CalDAV client that cannot see ETags cannot
          # do conditional writes. The preflight needs the WebDAV verbs spelled out
          # because browsers treat only GET/HEAD/POST as simple requests, so PROPFIND
          # and REPORT — every read Calino does — are blocked unless listed.
          calinoCors = ''
            @calino header Origin ${calinoOrigin}
            header @calino {
                Access-Control-Allow-Origin ${calinoOrigin}
                Access-Control-Allow-Credentials true
                Access-Control-Expose-Headers "ETag, DAV, Allow"
                Vary Origin
            }

            @calino_preflight {
                method OPTIONS
                header Origin ${calinoOrigin}
            }
            handle @calino_preflight {
                header Access-Control-Allow-Origin ${calinoOrigin}
                header Access-Control-Allow-Credentials true
                header Access-Control-Allow-Methods "GET, HEAD, PUT, POST, DELETE, PROPFIND, PROPPATCH, REPORT, OPTIONS, MKCOL, MKCALENDAR, COPY, MOVE"
                header Access-Control-Allow-Headers "Authorization, Content-Type, Depth, If-Match, If-None-Match, Destination, Overwrite, Prefer"
                header Access-Control-Max-Age 86400
                header Vary Origin
                respond 204
            }
          '';

          proxy = ''
            reverse_proxy http://${config.services.rustical.settings.http.bind} {
              header_up Host "${publicHost}"
            }
          '';
        in
        {
          # Both the module and the package come from nixpkgs-unstable; the stable
          # module has to be taken out of the way first, or the two collide on
          # `services.rustical`.

          # RustiCal — the CalDAV/CardDAV server the whole calendar stack hangs off:
          # calendar-syncer.nix writes into it, calino.nix reads from it in a browser,
          # and phones/Thunderbird point straight at it.
          services.rustical = {
            enable = true;
            package = upkgs.rustical;

            settings = {
              # Loopback only — Caddy is the single way in. See the note on `bind`
              # above for why this is not the module's default UNIX socket.
              http.bind = bind;

              # Kept on for calendar browsing and token revocation. CalDAV Basic auth
              # accepts app tokens and nothing else — `validate_app_token` is the
              # only credential path in crates/store/src/auth/middleware.rs — and the
              # frontend is where those are managed, the CLI notwithstanding.
              frontend.enabled = true;

              # WebDav Push lets DAVx5 learn about changes instead of polling. It
              # notifies through a push server the client nominates, so it only ever
              # sends what that client already asked for.
              dav_push.enabled = true;

              # Emulates the Nextcloud login flow, which is what makes DAVx5's
              # "Login with URL" flow generate its own app token instead of making us
              # paste one by hand.
              nextcloud_login.enabled = true;
            };
          };

          # Public, with ACME — the second service here to do that, after jellyfin.
          # Being internet-facing (over IPv6) is deliberate, and the exposure is
          # real: CalDAV accepts app tokens only, but the frontend accepts the
          # principal's password, and rustical does no rate limiting. Use a long
          # random password for the principal, and revoke app tokens per client
          # rather than sharing one.
          services.caddy.virtualHosts."https://${ipv6Host}" = {
            extraConfig = ''
              encode zstd gzip
              ${calinoCors}
              ${proxy}
            '';
          };
          services.caddy.virtualHosts."https://${publicHost}" = {
            extraConfig = ''
              encode zstd gzip
              ${calinoCors}
              ${proxy}
            '';
          };

          # Caddy would normally add this redirect itself for a site it serves over
          # HTTPS, but it skips that when another site already claims the same host
          # on port 80 — and caddy.nix's `http://*.${config.ogama.server.domain}` catch-all
          # claims every subdomain. Without this block, an http:// link lands on that
          # catch-all and gets a bare 404, which looks exactly like a dead service.
          # An explicit exact-host vhost outranks the wildcard.
          services.caddy.virtualHosts."http://${ipv6Host}" = {
            extraConfig = ''
              redir https://{host}{uri} permanent
            '';
          };

          # Tailnet path, plain HTTP: IPv4-only clients cannot use the IPv6 portal.
          # Fine for CalDAV, no good for the frontend (see the note at the top).
          services.caddy.virtualHosts."http://${tailHost}" = {
            extraConfig = ''
              encode zstd gzip

              ${calinoCors}
              ${proxy}
            '';
          };
        }
      );
    };

  flake.featureModules.home.rustical = sharedOptions;
}
