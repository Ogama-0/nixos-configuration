{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.opencloud.server.enable =
        lib.mkEnableOption "the OpenCloud file-sync/share server";
      options.ogama.server.opencloud.client.enable = lib.mkEnableOption "the OpenCloud desktop app ";
    };
in
{
  flake.featureModules.nixos.opencloud =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.server.opencloud.server.enable (
        let
          # "cloud.ipv6.ogama.me" (bare, ACME) for the public path,
          # "cloud.tail.ogama.me" for IPv4-only tailnet clients, and
          # "cloud.ogama.me" (VPS-fronted) for everyone else — the CNAME and
          # VPS registration for that last one are outside this repo.
          host = "cloud";
          publicHost = "${host}.${config.ogama.server.ipv6Host}";
          tailHost = "${host}.tail.${config.ogama.server.domain}";
          port = 9200; # services.opencloud.port's own default; free on this host.

          proxy = ''
            reverse_proxy http://127.0.0.1:${toString port} {
              # OpenCloud 308s to https when X-Forwarded-Proto doesn't match
              # `url`'s scheme below; Caddy sets that header from the
              # client's own connection, which is plain HTTP on the tailnet
              # vhost. Pin it so that vhost isn't redirected to a scheme it
              # never serves.
              header_up X-Forwarded-Proto https
              transport http {
                read_timeout  600s
                write_timeout 600s
              }
            }
          '';
        in
        {
          # First-boot admin password, read by idm when it provisions the
          # admin user. Add the actual value to sops/oserv.yaml by hand.
          sops.secrets."opencloud_admin_password" = {
            sopsFile = ../../../sops/oserv.yaml;
          };
          sops.templates."opencloud.env".content = ''
            ADMIN_PASSWORD=${config.sops.placeholder.opencloud_admin_password}
          '';

          services.opencloud = {
            enable = true;

            address = "127.0.0.1";
            inherit port;

            # Baked verbatim into config.json's server/theme/oidc URLs for
            # every vhost alike, so only the name below gets a working
            # browser UI until the VPS leg lands (others 404 the SPA's
            # config fetch with "missing or invalid config"). Switch to
            # "https://${host}.${config.ogama.server.domain}" once the VPS
            # registers that name, matching immich.nix's externalDomain.
            url = "https://${publicHost}";

            # If every internal LDAP bind (uid=idp/reva/libregraph,
            # ou=sysusers,o=libregraph-idm) starts failing with "not found":
            # upstream bug opencloud-eu/opencloud#3725. idm only seeds those
            # accounts the one time idm.boltdb doesn't exist; an interrupted
            # bootstrap leaves it behind empty, and every later start skips
            # reseeding forever. Fix: stop opencloud, delete
            # /etc/opencloud/opencloud.yaml AND this stateDir's idm.boltdb
            # together (never just one — see #2782), start once
            # uninterrupted with environment.OC_LOG_LEVEL = "debug" to
            # confirm "Bootstrapping IDM database" actually ran.
            stateDir = config.ogama.server.path.hdd.app.opencloud;

            environmentFile = config.sops.templates."opencloud.env".path;

            environment = {
              # Caddy already terminates TLS on both vhosts; no need for
              # OpenCloud's own self-signed cert on the loopback hop.
              PROXY_TLS = "false";
            };
          };

          # Public, with ACME — deliberately internet-facing, like jellyfin
          # and rustical.
          services.caddy.virtualHosts."${publicHost}" = {
            extraConfig = ''
              encode zstd gzip
              ${proxy}
            '';
          };

          # caddy.nix's "http://*.${domain}" catch-all claims port 80 for
          # every subdomain, so Caddy won't add this redirect on its own.
          services.caddy.virtualHosts."http://${publicHost}" = {
            extraConfig = ''
              redir https://{host}{uri} permanent
            '';
          };

          # IPv4-only tailnet clients can't reach the IPv6 public name.
          services.caddy.virtualHosts."http://${tailHost}" = {
            extraConfig = ''
              encode zstd gzip
              ${proxy}
            '';
          };
        }
      );
    };

  flake.featureModules.home.opencloud =
    {
      lib,
      config,
      upkgs,
      ...
    }:
    {
      imports = [ sharedOptions ];
      config = lib.mkIf config.ogama.server.opencloud.client.enable ({
        home.packages = with upkgs; [ opencloud-desktop ];
      });
    };
}
