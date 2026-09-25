{ cfg, config, ... }: {
  services.caddy = {
    enable = true;

    # Replaces the old security.acme.defaults.email — Caddy manages its
    # own ACME account/storage (in /var/lib/caddy), no separate
    # security.acme block needed at all.
    email = cfg.mail;

    virtualHosts = {
      "${cfg.server.domain}".extraConfig = ''
        respond 404
      '';

      # Catch-all for any subdomain that doesn't have its own explicit
      # vhost below. Deliberately kept plain HTTP (the "http://" scheme
      # prefix disables automatic HTTPS for this site): a real wildcard
      # cert needs a DNS-01 challenge, which isn't configured here.
      # Any *.${cfg.server.domain} request over HTTPS that isn't
      # jellyfin/immich.tail will simply fail the TLS handshake instead
      # of silently being served by an unrelated backend, unlike
      # nginx's implicit default_server fallback.
      "http://*.${cfg.server.domain}".extraConfig = ''
        respond 404
      '';

      # jellyfin.nix and immich.nix each add their own
      # services.caddy.virtualHosts.<name> entry — NixOS merges them in.
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
