{ cfg, ... }:
let path = "${cfg.home_path}/.jellyfin";
in {
  services.jellyfin = {
    enable = true;
    openFirewall = true;

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

    "d ${cfg.path.hdd.app.jellyfin}/audio              0755 ${cfg.user} users -"
    "d ${cfg.path.hdd.app.jellyfin}/audio/Books        0755 ${cfg.user} users -"
    "d ${cfg.path.hdd.app.jellyfin}/audio/livre_audio  0755 ${cfg.user} users -"
    "d ${cfg.path.hdd.app.jellyfin}/audio/Musique      0755 ${cfg.user} users -"

    "d ${cfg.path.hdd.app.jellyfin}/FILM               0777 ${cfg.user} users -" # 777 for allow qbittorrent, to write
    "d ${cfg.path.hdd.app.jellyfin}/SHOWS              0777 ${cfg.user} users -"
  ];
  services.nginx.virtualHosts = {
    "jellyfin.${cfg.server.domain}" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        proxyWebsockets = true;
      };
    };
  };

}
