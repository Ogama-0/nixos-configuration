{ pkgs, ... }: {
  networking.wg-quick.interfaces = {
    oscar = {
      autostart = false;

      privateKeyFile = "/etc/oscar-wg-vpn.key";
      address = [ "10.8.0.3/24" ];
      dns = [ "1.1.1.1" ];
      mtu = 1420;

      peers = [{
        publicKey = "Idz0+pG28XDSDTdAoJpmnoXd0IurrUKCwC0BNZcgkng=";
        presharedKeyFile = "/etc/oscar-preshare-wg-vpn.key";
        allowedIPs = [ "192.168.0.0/16" ];
        persistentKeepalive = 0;
        endpoint = "213.245.179.43:51820";
      }];
    };
  };

}
