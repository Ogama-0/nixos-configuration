{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.jellyfin.enable = lib.mkEnableOption "the Jellyfin media server";
    };
in
{
  flake.featureModules.nixos.jellyfin =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.server.jellyfin.enable (
        let
          path = "${config.ogama.identity.homePath}/.jellyfin";
          # Two names for the same backend: ipv6Host's AAAA points straight at
          # oserv, so Caddy can win ACME for it directly; publicHost is the
          # bare public name (AAAA now also direct, A still VPS-fronted).
          # Both vhosts force the Host header to publicHost, same as
          # opencloud.nix/immich.nix.
          publicHost = "jellyfin.${config.ogama.server.domain}";
          ipv6Host = "jellyfin.${config.ogama.server.ipv6Host}";

          proxy = ''
            reverse_proxy http://127.0.0.1:8096 {
              header_up Host "${publicHost}"
            }
          '';
        in
        {
          services.jellyfin = {
            enable = true;
            # openFirewall = true;

            cacheDir = "${path}/cache";
            configDir = "${path}/config";
            logDir = "${path}/log";
            dataDir = "${path}/data";

            group = "users";
            user = config.ogama.identity.user;
          };

          systemd.tmpfiles.rules = [
            "d ${path}          0755 ${config.ogama.identity.user} users -"
            "d ${path}/cache    0755 ${config.ogama.identity.user} users -"
            "d ${path}/config   0755 ${config.ogama.identity.user} users -"
            "d ${path}/log      0755 ${config.ogama.identity.user} users -"
            "d ${path}/data     0755 ${config.ogama.identity.user} users -"

            # the library folders qbittorrent downloads into are group-writable by
            # "users": it runs as qbittorrent:users with umask 0002, so finished
            # torrents stay manageable by jellyfin and samba (both ${config.ogama.identity.user}:users).
            "d ${config.ogama.server.path.hdd.app.jellyfin}/audio                  0775 ${config.ogama.identity.user} users -"
            "d ${config.ogama.server.path.hdd.app.jellyfin}/audio/Books            0775 ${config.ogama.identity.user} users -"
            "d ${config.ogama.server.path.hdd.app.jellyfin}/audio/Books/Audiobooks 0775 ${config.ogama.identity.user} users -"
            "d ${config.ogama.server.path.hdd.app.jellyfin}/audio/livre_audio      0755 ${config.ogama.identity.user} users -"
            "d ${config.ogama.server.path.hdd.app.jellyfin}/audio/Musique          0775 ${config.ogama.identity.user} users -"

            "d ${config.ogama.server.path.hdd.app.jellyfin}/FILM                   0775 ${config.ogama.identity.user} users -"
            "d ${config.ogama.server.path.hdd.app.jellyfin}/SHOWS                  0775 ${config.ogama.identity.user} users -"
          ];

          services.caddy.virtualHosts."https://${ipv6Host}" = {
            extraConfig = proxy;
          };
          services.caddy.virtualHosts."https://${publicHost}" = {
            extraConfig = proxy;
          };

          # caddy.nix's "http://*.${domain}" catch-all claims port 80 for
          # every subdomain, so Caddy won't add this redirect on its own.
          services.caddy.virtualHosts."http://${ipv6Host}" = {
            extraConfig = ''
              redir https://{host}{uri} permanent
            '';
          };
          # to bypass ipv6 limitation at least for device in tailnet
          services.caddy.virtualHosts."http://jellyfin.tail.${config.ogama.server.domain}" = {
            extraConfig = ''
              reverse_proxy http://127.0.0.1:8096
            '';
          };

          # services.nginx.virtualHosts."jellyfin.${config.ogama.server.domain}" = {
          #   enableACME = true;
          #   forceSSL = true;

          #   locations."/" = {
          #     proxyPass = "http://127.0.0.1:8096";
          #     proxyWebsockets = true;
          #   };
          # };
        }
      );
    };

  flake.featureModules.home.jellyfin = sharedOptions;
}
