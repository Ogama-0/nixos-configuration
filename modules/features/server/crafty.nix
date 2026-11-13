{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.crafty.enable = lib.mkEnableOption "the Crafty minecraft panel (needs docker)";
    };
in
{
  flake.featureModules.nixos.crafty =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.server.crafty.enable (
        let
          path = "${config.ogama.identity.homePath}/.crafty";
        in
        {
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
                extraOptions = [
                  "--dns=8.8.8.8"
                  "--dns=4.4.4.4"
                ];

                autoStart = true;
              };
            };
          };
          systemd.tmpfiles.rules = [
            "d ${path}        0755 ${config.ogama.identity.user} users -"
            "d ${path}/backups 0755 ${config.ogama.identity.user} users -"
            "d ${path}/logs    0755 ${config.ogama.identity.user} users -"
            "d ${path}/servers 0755 ${config.ogama.identity.user} users -"
            "d ${path}/config  0755 ${config.ogama.identity.user} users -"
            "d ${path}/import  0755 ${config.ogama.identity.user} users -"
          ];
          networking.firewall = {
            allowedTCPPorts = [
              30001
              8123
              19132
            ];
            allowedTCPPortRanges = [
              {
                from = 25500;
                to = 25600;
              }
            ];
          };

          services.nginx.virtualHosts."crafty.${config.ogama.server.domain}" = {
            enableACME = true;
            forceSSL = true;

            locations."/" = {
              proxyPass = "https://127.0.0.1:30001";
              proxyWebsockets = true;
            };
          };
        }
      );
    };

  flake.featureModules.home.crafty = sharedOptions;
}
