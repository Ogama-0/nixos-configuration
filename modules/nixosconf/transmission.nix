{ cfg, ... }:
let Jellyfin_torrent_path = "${cfg.HDD_path}/appdata/jellyfin/FILM/TORRENT";
in {
  services.transmission = {
    enable = true; # Enable transmission daemon
    openRPCPort = true; # Open firewall for RPC
    openFirewall = true;
    openPeerPorts = true;
    settings = { # Override default settings
      rpc-bind-address = "0.0.0.0"; # Bind to own IP
      peer-port = 51413;
      rpc-whitelist = "127.0.0.1,100.*.*.*,192.168.1.*"; # Tails scale hosts
      download-dir = Jellyfin_torrent_path;
    };
  };
}
