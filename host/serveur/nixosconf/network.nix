{ config, pkgs, ... }:
{
  networking = {

    networkmanager.enable = true;
    defaultGateway = {
      address = "192.168.1.1";
      interface = "eno1";
    };
    # IPv6 default route comes from router advertisements (see ipv6.addresses
    # comment below) rather than being pinned here.

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
      # No static ipv6.addresses here: the ISP delegates the LAN's IPv6
      # prefix dynamically (DHCPv6-PD) and rotates it from time to time, so a
      # hardcoded global address silently goes stale and unreachable. Get the
      # address via SLAAC instead; tempAddress "disabled" keeps it a single
      # stable (non-rotating-per-privacy-extension) address so DNS/ddns has
      # one consistent value to publish.
      tempAddress = "disabled";
    };

  };

}
