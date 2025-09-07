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

      "crafty.${cfg.server.domain}" = (SSL // {
        locations."/" = {
          proxyPass = "https://127.0.0.1:30001";
          proxyWebsockets = true;
        };
      });

      "joplin.${cfg.server.domain}" = (SSL // {
        locations."/" = {
          proxyPass = "http://127.0.0.1:22300";
          proxyWebsockets = true;
        };
      });

      "immich.${cfg.server.domain}" = (SSL // {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://[::1]:${toString config.services.immich.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
          extraConfig = ''
            client_max_body_size 50000M;
            proxy_read_timeout   600s;
            proxy_send_timeout   600s;
            send_timeout         600s;
          '';
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
