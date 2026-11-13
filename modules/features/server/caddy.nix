{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.caddy.enable = lib.mkEnableOption "the reverse proxy every service is published behind";
    };
in
{
  flake.featureModules.nixos.caddy =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.server.caddy.enable (
        {
          services.caddy = {
            enable = true;

            # Replaces the old security.acme.defaults.email — Caddy manages its
            # own ACME account/storage (in /var/lib/caddy), no separate
            # security.acme block needed at all.
            email = config.ogama.identity.mail;

            # Exposes caddy_http_requests_total / caddy_http_request_duration_seconds
            # (with a "code" label) on the admin API's default 127.0.0.1:2019/metrics,
            # scraped by grafana.nix's Prometheus job.
            globalConfig = ''
              metrics
            '';

            virtualHosts = {
              # Plain HTTP for the same reason as the wildcard below, plus one
              # of its own: the apex A record is OVH's redirect.ovh.net
              # (213.186.33.5) and its AAAA is elsewhere again - neither is this
              # host. Left bare, Caddy turns on automatic HTTPS and retries ACME
              # forever: http-01 follows OVH's redirect to
              # www.${config.ogama.server.domain}, which has no record at all
              # (NXDOMAIN), and tls-alpn-01 is refused outright. That loop
              # re-fired on every reload until it earned a Let's Encrypt 429.
              # The block only ever answers 404, so it loses nothing by never
              # holding a certificate.
              "http://${config.ogama.server.domain}".extraConfig = ''
                respond 404
              '';

              # Catch-all for any subdomain that doesn't have its own explicit
              # vhost below. Deliberately kept plain HTTP (the "http://" scheme
              # prefix disables automatic HTTPS for this site): a real wildcard
              # cert would need a DNS-01 challenge, which isn't configured here.
              # Any *.${config.ogama.server.domain} request over HTTPS that isn't
              # jellyfin/rustical will simply fail the TLS handshake instead of
              # silently being served by an unrelated backend, unlike nginx's
              # implicit default_server fallback.
              #
              # Side effect worth knowing: because this site claims port 80 for
              # every subdomain, Caddy will *not* generate the usual
              # HTTP->HTTPS redirect for a site that does use TLS — see the
              # hand-written redirect in rustical.nix.
              "http://*.${config.ogama.server.domain}".extraConfig = ''
                respond 404
              '';

              # jellyfin.nix and immich.nix each add their own
              # services.caddy.virtualHosts.<name> entry — NixOS merges them in.
            };
          };

          networking.firewall.allowedTCPPorts = [
            80
            443
          ];
        }
      );
    };

  flake.featureModules.home.caddy = sharedOptions;
}
