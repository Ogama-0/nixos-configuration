{ config, pkgs, ... }:
{
  networking = {

    networkmanager.enable = true;
    # eno1's addressing is fully handled by the scripted `interfaces.eno1`
    # config below (static IPv4 + kernel SLAAC for IPv6). NetworkManager
    # otherwise auto-creates its own profile for the interface and defaults
    # IPv6 to link-local-only, which silently blocks the SLAAC address and
    # breaks anything depending on oserv's public IPv6. Keep NM off it
    # entirely rather than trying to reconcile two owners of the interface.
    networkmanager.unmanaged = [ "interface-name:eno1" ];
    # eno1 has forwarding enabled (Tailscale/Docker need it), and per the
    # kernel's IPv6 semantics accept_ra=1 is a no-op once forwarding is on
    # for that interface — only accept_ra=2 forces RA/SLAAC processing
    # (address + default route) regardless of forwarding.
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

  boot.kernel.sysctl."net.ipv6.conf.eno1.accept_ra" = 2;

}
