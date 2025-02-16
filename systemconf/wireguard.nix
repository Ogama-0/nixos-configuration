{ pkgs, ... }: {
  networking.wireguard.interfaces = let
    # [Peer] section -> Endpoint
    server_ip = "213.245.179.43";
  in {
    oscar = {
      # [Interface] section -> Address
      ips = [ "10.8.0.3/24" ];

      # [Peer] section -> Endpoint:port
      listenPort = 51820;

      # Path to the private key file.
      privateKeyFile = "/etc/oscar-wg-vpn.key";

      peers = [{
        # [Peer] section -> PublicKey
        publicKey = "Idz0+pG28XDSDTdAoJpmnoXd0IurrUKCwC0BNZcgkng=";
        # [Peer] section -> AllowedIPs
        allowedIPs = [ "0.0.0.0/0" "::/0" ];
        # [Peer] section -> Endpoint:port
        endpoint = "${server_ip}:51820";
        persistentKeepalive = 25;
      }];
    };
  };
}
