{ pkgs, ... }: {
  networking.wg-quick.interfaces = {
    oscar = {
      autostart = false;

      privateKeyFile = "/etc/oscar-wg-vpn.key";
      address = [ "10.100.0.2/32" ];
      dns = [ "1.1.1.1" ];
      mtu = 1420;

      peers = [{
        publicKey = "n2tJRRBGgDfnYGOCmvLnGNwDoNnkzWgnL0NQdWTY+DI=";
        # presharedKeyFile = "/etc/oscar-preshare-wg-vpn.key";
        allowedIPs = [ "192.168.0.0/16" ];
        persistentKeepalive = 0;
        # endpoint = "213.245.179.43:51820";
        endpoint = "wireguard.ogama.me:51820";
      }];
    };
  };

}
