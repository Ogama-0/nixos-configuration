{ cfg, ... }:
let path = "${cfg.home_path}/.joplin";
in {
  # sudo podman network create joplinnet
  virtualisation.oci-containers = {
    containers = {
      joplindb = {
        image = "postgres:16";
        volumes = [ "${path}/joplindb:/var/lib/postgresql/data" ];
        ports = [ "5433:5432" ];

        environment = {
          POSTGRES_PASSWORD = "postgres";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "joplin";
        };
      };

      joplin = {
        dependsOn = [ "joplindb" ];
        image = "joplin/server:latest";
        ports = [ "22300:22300" ];

        environment = {
          APP_PORT = "22300";
          APP_BASE_URL = "https://joplin.${cfg.server.domain}";
          DB_CLIENT = "pg";
          POSTGRES_PASSWORD = "postgres";
          POSTGRES_DATABASE = "joplin";
          POSTGRES_USER = "postgres";
          POSTGRES_HOST = "host.containers.internal";
          POSTGRES_PORT = "5433";
          TZ = "Etc/UTC";
          PUID = "1000";
          PGID = "1000";
        };
        volumes = [ "${path}/config:/config" ];

        autoStart = true;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${path}          0755 ${cfg.user} users -"
    "d ${path}/config   0755 ${cfg.user} users -"
    "d ${path}/joplindb 0755 ${cfg.user} users -"
  ];
  networking.firewall.allowedTCPPorts = [ 22300 ];
}
