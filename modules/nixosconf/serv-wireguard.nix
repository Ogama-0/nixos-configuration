{ cfg, pkgs, ... }:
let path = "${cfg.home_path}/.wireguard";
in {
  # enable NAT
  networking.nat.enable = true;
  networking.nat.externalInterface = "eno1";
  networking.nat.internalInterfaces = [ "wg0" ];
  networking.firewall = { allowedUDPPorts = [ 51820 ]; };

  networking.wireguard.enable = true;
  networking.wireguard.interfaces = {
    wg0 = {

      # generatePrivateKeyFile = true;
      privateKeyFile = "${path}/keys/private";
      ips = [ "10.100.0.1/24" ];

      listenPort = 51820;

      # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
      # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
      # postSetup = ''
      #   ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o eno1 -j MASQUERADE
      # '';

      # # This undoes the above command
      # postShutdown = ''
      #   ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o eno1 -j MASQUERADE
      # '';

      peers = [
        # {
        #   name = "backup";
        #   publicKey = "{client public key}";
        #   allowedIPs = [ "10.100.0.2/24" ];
        # }
        {
          name = "oscar";
          publicKey = "wPOD5pw6EkBLSHqWcOTwY+fmG5V238OlpYQj5G1SRi4=";
          allowedIPs = [ "10.100.3.0/24" ];
        }
      ];
    };
  };
  systemd.tmpfiles.rules = [
    "d ${path}      0755 ${cfg.user} users -"
    "d ${path}/keys 0755 ${cfg.user} users -"
  ];
}
