{ cfg, ... }:

let
  path = "${cfg.home_path}/.jellyfin";
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
    user = cfg.user;
  };

  systemd.tmpfiles.rules = [
    "d ${path}          0755 ${cfg.user} users -"
    "d ${path}/cache    0755 ${cfg.user} users -"
    "d ${path}/config   0755 ${cfg.user} users -"
    "d ${path}/log      0755 ${cfg.user} users -"
    "d ${path}/data     0755 ${cfg.user} users -"

    # the library folders qbittorrent downloads into are group-writable by
    # "users": it runs as qbittorrent:users with umask 0002, so finished
    # torrents stay manageable by jellyfin and samba (both ${cfg.user}:users).
    "d ${cfg.path.hdd.app.jellyfin}/audio                  0775 ${cfg.user} users -"
    "d ${cfg.path.hdd.app.jellyfin}/audio/Books            0775 ${cfg.user} users -"
    "d ${cfg.path.hdd.app.jellyfin}/audio/Books/Audiobooks 0775 ${cfg.user} users -"
    "d ${cfg.path.hdd.app.jellyfin}/audio/livre_audio      0755 ${cfg.user} users -"
    "d ${cfg.path.hdd.app.jellyfin}/audio/Musique          0775 ${cfg.user} users -"

    "d ${cfg.path.hdd.app.jellyfin}/FILM                   0775 ${cfg.user} users -"
    "d ${cfg.path.hdd.app.jellyfin}/SHOWS                  0775 ${cfg.user} users -"
  ];

  services.caddy.virtualHosts."jellyfin.${cfg.host.ipv6}" = {
    extraConfig = ''
      reverse_proxy http://127.0.0.1:8096
    '';
  };
  # to bypass ipv6 limitation at least for device in tailnet
  services.caddy.virtualHosts."http://jellyfin.tail.${cfg.domain}" = {
    extraConfig = ''
      reverse_proxy http://127.0.0.1:8096
    '';
  };

  # services.nginx.virtualHosts."jellyfin.${cfg.server.domain}" = {
  #   enableACME = true;
  #   forceSSL = true;

  #   locations."/" = {
  #     proxyPass = "http://127.0.0.1:8096";
  #     proxyWebsockets = true;
  #   };
  # };
}
