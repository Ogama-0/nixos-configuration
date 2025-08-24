{ cfg, ... }:
let path = "${cfg.home_path}/.joplin";
in {
  # sudo podman network create joplinnet
  virtualisation.oci-containers = {
    backend = "podman";

    containers = {
      joplindb = {
        image = "postgres:16";
        volumes = [ "${path}/joplindb:/var/lib/postgresql/data" ];
        # ports = [ "5432:5432" ];
        extraOptions = [ "--network=joplinnet" ];

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
        extraOptions = [ "--network=joplinnet" ];

        environment = {
          APP_PORT = "22300";
          APP_BASE_URL = "http://${cfg.server.ip4}:22300";
          DB_CLIENT = "pg";
          POSTGRES_PASSWORD = "postgres";
          POSTGRES_DATABASE = "joplin";
          POSTGRES_USER = "postgres";
          POSTGRES_PORT = "5432";
          POSTGRES_HOST = "joplindb";
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
