{ cfg, ... }: {
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
        locations."/" = {
          # proxyWebsockets = true;
          extraConfig = "return 404;";
        };
      };

      "jellyfin.${cfg.server.domain}" = (SSL // {
        locations."/" = {
          proxyPass = "http://127.0.0.1:8096";
          proxyWebsockets = true;
        };
      });

      "joplin.${cfg.server.domain}" = (SSL // {
        locations."/" = {
          proxyPass = "http://127.0.0.1:22300";
          proxyWebsockets = true;
        };
      });
      # "objectifFarm.${cfg.server.domain}" = {
      #   enableACME = true;
      #   locations."/" = {
      #     proxyPass = "http://127.0.0.1:25569";
      #     proxyWebsockets = true;
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
