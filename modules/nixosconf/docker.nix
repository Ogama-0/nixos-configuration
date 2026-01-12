{ config, pkgs, ... }: {

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;

    # Docker root, pas rootless
    rootless.enable = false;

    # Options daemon Docker (ipv6 activé)
    daemon.settings = {
      ipv6 = true;
      fixed-cidr-v6 = "fd00::/80";

      # Optionnel : DNS publics (IPv4 + IPv6)
      dns =
        [ "1.1.1.1" "8.8.8.8" "2001:4860:4860::8888" "2001:4860:4860::8844" ];
    };
  };
  networking.firewall.trustedInterfaces = [ "docker0" "podman0" ];
}
