{ pkgs, config, cfg, ... }:

let
  immichHost = "immich.${cfg.server.domain}";
  immichTailHost = "immich.tail.${cfg.server.domain}";
  immichRoot = "${cfg.path.hdd.app.immich}";

in {
  # systemd.tmpfiles.rules = [
  #   "d ${immichRoot}                0755 immich immich -"
  #   "d ${immichRoot}/upload         0755 immich immich -"
  #   "d ${immichRoot}/encoded-video  0755 immich immich -"
  #   "d ${immichRoot}/thumbs         0755 immich immich -"
  #   "d ${immichRoot}/library        0755 immich immich -"
  #   "d ${immichRoot}/profile        0755 immich immich -"
  #   "d ${immichRoot}/backups        0755 immich immich -"
  # ];
  # environment.sessionVariables.IMMICH_IGNORE_MOUNT_CHECK_ERRORS = "true";

  services.immich = {
    enable = true;
    port = 2283;
    mediaLocation = "${immichRoot}";

    database = {
      enable = true;
      createDB = true;
    };
    machine-learning.enable = true;

    redis = {
      enable = true;
      port = 2281;
    };
    settings.server.externalDomain = # [
      "https://${immichHost}" # internet
      # "https://${immichTailHost}" # tailnet
      # ]
    ;

    openFirewall = true;
  };

  services.nginx.virtualHosts = {

    "${immichHost}" = {

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
    };
    "${immichTailHost}" = {

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
    };
  };
}
