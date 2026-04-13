{ pkgs, cfg, ... }:
let
  path = "${cfg.home_path}/.joplin";
  subdomain = "joplin";
  port = 22300;
  dockerNetwork = "joplin-net";
in {
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      joplindb = {
        image = "postgres:16";
        volumes = [ "${path}/joplindb:/var/lib/postgresql/data" ];
        extraOptions = [ "--network=${dockerNetwork}" ];
        # ports = [ "5433:5432" ];

        environment = {
          POSTGRES_PASSWORD = "postgres";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "joplin";
        };
      };

      joplin = {
        dependsOn = [ "joplindb" ];
        image = "joplin/server:latest";
        ports = [ "${toString port}:22300" ];

        environment = {
          APP_PORT = "${toString port}";
          APP_BASE_URL = "https://${subdomain}.tail.${cfg.server.domain}";
          DB_CLIENT = "pg";
          POSTGRES_PASSWORD = "postgres";

          POSTGRES_DATABASE = "joplin";
          POSTGRES_USER = "postgres";
          POSTGRES_HOST = "joplindb";
          POSTGRES_PORT = "5432";
          TZ = "Etc/UTC";
          PUID = "1000";
          PGID = "1000";
        };
        volumes = [ "${path}/config:/config" ];
        extraOptions = [ "--network=${dockerNetwork}" ];

        autoStart = true;
      };
    };
  };
  systemd.tmpfiles.rules = [
    "d ${path}          0755 ${cfg.user} users -"
    "d ${path}/config   0755 ${cfg.user} users -"
    "d ${path}/joplindb 0755 ${cfg.user} users -"
  ];
  networking.firewall.allowedTCPPorts = [ port ];

  services.nginx.virtualHosts = cfg.ngnix.mkVhost {
    inherit subdomain;
    proxyPass = "http://127.0.0.1:${toString port}";
  };
}
