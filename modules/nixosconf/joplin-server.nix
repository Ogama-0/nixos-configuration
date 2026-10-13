{ pkgs, cfg, ... }:
let
  path = "${cfg.home_path}/.joplin";
  subdomain = "joplin";
  host = "${subdomain}.tail.${cfg.server.domain}";
  port = 22300;
  dockerNetwork = "joplin-net";
in {
  # The user-defined bridge both containers sit on. oci-containers does not
  # create docker networks, so without this unit the containers only start
  # on a machine where someone ran `docker network create joplin-net` by
  # hand — and joplin resolves its database by the container name
  # "joplindb", which only works on a user-defined bridge (the default
  # bridge has no embedded DNS).
  systemd.services."docker-network-${dockerNetwork}" = {
    path = [ pkgs.docker ];
    after = [ "docker.service" "docker.socket" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      docker network inspect ${dockerNetwork} >/dev/null 2>&1 \
        || docker network create ${dockerNetwork}
    '';
  };

  systemd.services.docker-joplin = {
    after = [ "docker-network-${dockerNetwork}.service" ];
    requires = [ "docker-network-${dockerNetwork}.service" ];
  };
  systemd.services.docker-joplindb = {
    after = [ "docker-network-${dockerNetwork}.service" ];
    requires = [ "docker-network-${dockerNetwork}.service" ];
  };

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      joplindb = {
        image = "postgres:16";
        volumes = [ "${path}/joplindb:/var/lib/postgresql/data" ];
        extraOptions = [ "--network=${dockerNetwork}" ];
        # No ports: reachable only from the joplin container over the bridge.

        # POSTGRES_PASSWORD is only read when the data directory is first
        # initialised, so this value is already baked into the existing
        # volume — moving it to sops now would not change the password the
        # database actually accepts, it would only desynchronise the two.
        # Left as-is deliberately; the socket is not published anywhere.
        environment = {
          POSTGRES_PASSWORD = "postgres";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "joplin";
        };
      };

      joplin = {
        dependsOn = [ "joplindb" ];
        image = "joplin/server:latest";
        # Loopback-only: Caddy is the only thing that should reach it.
        ports = [ "127.0.0.1:${toString port}:22300" ];

        environment = {
          APP_PORT = "${toString port}";
          # Must match the scheme the vhost below actually serves. This said
          # https://, which Joplin then used to build the links and API base
          # it hands to clients — over a tailnet vhost that only speaks
          # plain HTTP.
          APP_BASE_URL = "http://${host}";
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

  # No networking.firewall.allowedTCPPorts: the container publishes on
  # loopback and the only way in is the Caddy vhost, same as every other
  # service on this host.

  services.caddy.virtualHosts."http://${host}" = {
    extraConfig = ''
      reverse_proxy http://127.0.0.1:${toString port}
    '';
  };
}
