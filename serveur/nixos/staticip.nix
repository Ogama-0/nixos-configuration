{ config, pkgs, ... }:

{
  networking.useNetworkd = true; # on utilise systemd-networkd

  networking.interfaces.eno1 = {
    useDHCP = false; # désactiver DHCP
    ipv4.addresses = [{
      address = "192.168.10.50"; # IP que tu veux donner au serveur
      prefixLength = 24; # masque réseau (24 = 255.255.255.0)
    }];
  };
  networking.defaultGateway = {
    address = "192.168.10.1";
    interface = "eno1";
  };

  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
}
