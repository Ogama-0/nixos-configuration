{ cfg, config, ... }: {
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts = let
      SSL = {
        enableACME = true;
        forceSSL = true;

      };
    in {
      "${cfg.server.domain}" =
        (SSL // { locations."/".extraConfig = "return 404;"; });

      "*.${cfg.server.domain}" = {
        locations."/" = { extraConfig = "return 404;"; };
      };

      # jellyfin
      # crafty
      # joplin
      # immich
      # qbittorrent

      # TEMPLATE :
      #
      # services.nginx.virtualHosts = {
      #   "${appname}.${cfg.server.domain}" = {

      #     enableACME = true;
      #     forceSSL = true;

      #     locations."/" = {
      #       proxyPass = "http://127.0.0.1:${port}";
      #       proxyWebsockets = true;
      #     };
      #   };
      # };

    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = cfg.mail;
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
