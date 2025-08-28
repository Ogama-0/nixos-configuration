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

      peers = [{
        name = "oscar";
        publicKey = "S6aQSsPxYBV7vjSyLYg04qyCHwvwzf/ybYdMb9kCBxQ=";
        allowedIPs = [ "10.100.0.2/32" ];

      }];
    };
  };
  systemd.tmpfiles.rules = [
    "d ${path}      0755 ${cfg.user} users -"
    "d ${path}/keys 0755 ${cfg.user} users -"
  ];
}
