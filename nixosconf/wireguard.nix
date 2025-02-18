{ pkgs, ... }: {
  # networking.firewall = {
  #   checkReversePath = false;

  #   allowedUDPPorts = [ 67 51820 ];
  # };

  # networking.wg-quick.interfaces = let
  #   # [Peer] section -> Endpoint
  #   server_ip = "213.245.179.43";
  # in {
  #   oscar = {
  #     # [Interface] section -> Address
  #     address = [ "10.8.0.3/24" ];
  #     autostart = false;
  #     dns = [ "1.1.1.1" ];
  #     mtu = 1420;
  #     # [Peer] section -> Endpoint:port
  #     listenPort = 51820;

  #     # Path to the private key file.
  #     privateKeyFile = "/etc/oscar-wg-vpn.key";

  #     # postUp postDown preUp preDown

  #     peers = [{
  #       # [Peer] section -> PublicKey
  #       publicKey = "Idz0+pG28XDSDTdAoJpmnoXd0IurrUKCwC0BNZcgkng=";
  #       # [Peer] section -> AllowedIPs
  #       allowedIPs = [ "0.0.0.0/0" "::/0" ];
  #       # [Peer] section -> Endpoint:port
  #       endpoint = "${server_ip}:51820";
  #       persistentKeepalive = 25;
  #     }];
  #   };
  # };

  # marche mais pas postUP/postDown
  # networking.wg-quick.interfaces.oscar = {
  #   configFile = "/etc/nixos/wireguard/oscar.conf";
  #   postUp = ''
  #     sudo mount -t cifs //192.168.10.51/oscar /home/ogama/documents/nas -o username=oscar,password=mdpelo,uid=$(id -u),gid=$(id -g)
  #     echo bonjour
  #   '';

  #   preDown = ''
  #     sudo umount /home/ogama/documents/nas
  #   '';
  #   autostart = false;
  # };

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
        allowedIPs = [ "0.0.0.0/0" "::/0" ];
        persistentKeepalive = 0;
        endpoint = "213.245.179.43:51820";
      }];
    };
  };

}
