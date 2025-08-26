{ config, pkgs, ... }:

{
  networking.useNetworkd = true;

  networking.interfaces.eno1 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.10.50";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = {
    address = "192.168.10.1";
    interface = "eno1";
  };

  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
}
