{ cfg, ... }:
let
  qb_root = "/home/${cfg.user}/.qbittorrent";
  save_path = "${qb_root}/torrent_file";
  hdd_file_path = "${cfg.path.hdd.app.qbittorrent}";
  torrent_file_path = "${hdd_file_path}/torrents";
  incomplet_file_path = "${hdd_file_path}/logs";
  movie_file_path = "${cfg.path.hdd.app.jellyfin}/FILM";
in {
  services.qbittorrent = {
    enable = true;
    openFirewall = true;
  };

  services.nginx.virtualHosts = {
    "qbittorrent.${cfg.server.domain}" = {

      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:8080";
        proxyWebsockets = true;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${qb_root}                0755 qbittorrent qbittorrent -"
    "d ${save_path}              0755 qbittorrent qbittorrent -"
    "d ${hdd_file_path}          0755 qbittorrent qbittorrent -"
    "d ${torrent_file_path}      0755 qbittorrent qbittorrent -"
    "d ${incomplet_file_path}    0755 qbittorrent qbittorrent -"
  ];
}
