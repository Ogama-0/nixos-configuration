{ cfg, ... }:
let path = "${cfg.home_path}/.crafty";
in {
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      crafty = {
        image = "registry.gitlab.com/crafty-controller/crafty-4:latest";
        ports = [
          "[::]:25500-25600:25500-25600" # java ipv6
          # "25500-25600:25500-25600" # java ipv6
          "8123:8123" # DYNMAP (not use)
          "30001:8443" # web with nginx
        ];
        environment = {
          TZ = "Etc/UTC";
          JDK_JAVA_OPTIONS = "-Djava.net.preferIPv4Stack=true";
        };
        volumes = [
          "${path}/backups:/crafty/backups"
          "${path}/logs:/crafty/logs"
          "${path}/servers:/crafty/servers"
          "${path}/config:/crafty/app/config"
          "${path}/import:/crafty/import"
        ];
        extraOptions = [ "--dns=8.8.8.8" "--dns=4.4.4.4" ];

        autoStart = true;
      };
    };
  };
  systemd.tmpfiles.rules = [
    "d ${path}        0755 ${cfg.user} users -"
    "d ${path}/backups 0755 ${cfg.user} users -"
    "d ${path}/logs    0755 ${cfg.user} users -"
    "d ${path}/servers 0755 ${cfg.user} users -"
    "d ${path}/config  0755 ${cfg.user} users -"
    "d ${path}/import  0755 ${cfg.user} users -"
  ];
  networking.firewall = {
    allowedTCPPorts = [ 30001 8123 19132 ];
    allowedTCPPortRanges = [{
      from = 25500;
      to = 25600;
    }];
  };
  services.nginx.virtualHosts = {
    "crafty.${cfg.server.domain}" = {

      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "https://127.0.0.1:30001";
        proxyWebsockets = true;
      };
    };

  };

}
