{ pkgs, config, cfg, ... }:
let
  Jellyfin_torrent_path = "${cfg.path.hdd.app.jellyfin}/FILM/TORRENT";
  home = "${cfg.path.HDD_app}/transmission";
in {
  services.transmission = {
    package = pkgs.transmission_4;
    enable = true; # Enable transmission daemon
    openRPCPort = true; # Open firewall for RPC
    openFirewall = true;
    openPeerPorts = true;
    settings = { # Override default settings
      inherit home;
      rpc-bind-address = "0.0.0.0"; # Bind to own IP
      peer-port = 51413;
      rpc-host-whitelist-enabled = false;
      # rpc-whitelist =
      #   "127.0.0.1,100.*.*.*,192.168.1.* *.*.*.*"; # Tails scale hosts
      download-dir = Jellyfin_torrent_path;

      watch-dir = "${home}/to_download";
      watch-dir-enabled = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d ${home}                0755 transmission transmission -"
    "d ${home}/to_download    0755 transmission transmission -"
  ];
}
