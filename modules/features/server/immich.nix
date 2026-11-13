{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.immich.enable = lib.mkEnableOption "the Immich photo server";
    };
in
{
  flake.featureModules.nixos.immich =
    { lib, upkgs, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.server.immich.enable (
        let
          immichHost = "immich.${config.ogama.server.domain}";
          immichTailHost = "immich.tail.${config.ogama.server.domain}";
          immichRoot = "${config.ogama.server.path.hdd.app.immich}";
        in
        {
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
            package = upkgs.immich;
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
            settings.server.externalDomain = "https://${immichHost}";
          };

          services.caddy.virtualHosts."https://immich.${config.ogama.server.ipv6Host}" = {
            extraConfig = ''
              reverse_proxy http://[::1]:${toString config.services.immich.port} {
                transport http {
                  read_timeout  600s
                  write_timeout 600s
                }
              }
            '';
          };

          # services.nginx.virtualHosts.${immichTailHost} = {
          #   enableACME = false;
          #   forceSSL = false;

          #   locations."/" = {
          #     proxyPass = "http://[::1]:${toString config.services.immich.port}";
          #     proxyWebsockets = true;
          #     recommendedProxySettings = true;

          #     extraConfig = ''
          #       client_max_body_size 50000M;
          #       proxy_read_timeout   600s;
          #       proxy_send_timeout   600s;
          #       send_timeout         600s;
          #     '';
          #   };
          # };
        }
      );
    };

  flake.featureModules.home.immich = sharedOptions;
}
