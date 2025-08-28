{ config, pkgs, ... }:

{
  networking = {

    networkmanager.enable = true;
    defaultgateway = {
      address = "192.168.10.1";
      interface = "eno1";
    };

    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    domain = "ogama.me";
    search = [ "ogama.me" ];
    # useNetworkd = true;

    interfaces.eno1 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = "192.168.10.50";
        prefixLength = 24;
      }];
    };

  };

}
