{ config, pkgs, ... }:
let

  external-ip6 = "2a02:842a:830b:901::10";

in {
  networking = {

    networkmanager.enable = true;
    defaultGateway = {
      address = "192.168.1.1";
      interface = "eno1";
    };
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eno1";
    };

    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    domain = "ogama.me";
    search = [ "ogama.me" ];
    # useNetworkd = true;

    interfaces.eno1 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = "192.168.1.50";
        prefixLength = 24;
      }];
      ipv6.addresses = [{
        address = external-ip6;
        prefixLength = 64;
      }];
    };

  };

}
