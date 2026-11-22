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
          # One public-facing name: "cloud.ogama.me", VPS-fronted, no tailnet
          # fallback. oserv is IPv6-only at home, so that name's own AAAA
          # record points at the VPS, not here — oserv can never win an ACME
          # challenge for it directly (confirmed: both tls-alpn-01 and
          # http-01 fail against the VPS). Caddy here instead holds the cert
          # on "cloud.ipv6.ogama.me", whose AAAA does point at oserv; the VPS
          # terminates TLS for the public name and re-dials oserv over HTTPS
          # on this ipv6 name, same as jellyfin/immich/rustical/lsi/wakapi.
          # Registering "cloud" on the VPS side is manual, per-name, and
          # outside this repo — ask for it, same as every other public name.
          host = "cloud";
          publicHost = "${host}.${config.ogama.server.domain}";
          ipv6Host = "${host}.${config.ogama.server.ipv6Host}";
          port = 9200; # services.opencloud.port's own default; free on this host.

          proxy = ''
            reverse_proxy http://127.0.0.1:${toString port} {
              header_up Host "${publicHost}"
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
              # Caddy already terminates TLS on the vhost; no need for
              # OpenCloud's own self-signed cert on the loopback hop.
              PROXY_TLS = "false";
            };
          };

          # Public, with ACME — deliberately internet-facing, like jellyfin
          # and rustical.
          services.caddy.virtualHosts."https://${ipv6Host}" = {
            extraConfig = ''
              encode zstd gzip
              ${proxy}
            '';
          };
          services.caddy.virtualHosts."https://${publicHost}" = {
            extraConfig = ''
              encode zstd gzip
              ${proxy}
            '';
          };

          # caddy.nix's "http://*.${domain}" catch-all claims port 80 for
          # every subdomain, so Caddy won't add this redirect on its own.
          services.caddy.virtualHosts."http://${ipv6Host}" = {
            extraConfig = ''
              redir https://{host}{uri} permanent
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
