{ cfg, ... }:
let path = "${cfg.home_path}/.crafty";
in {
  virtualisation.oci-containers.containers = {
    crafty = {
      image = "registry.gitlab.com/crafty-controller/crafty-4:latest";
      ports = [
        "25500-25600:25500-25600" # java
        "19132:19132/udp" # Bedrock
        "8123:8123" # DYNMAP
        "30001:8443" # lien vers le panel
      ];
      environment = { TZ = "Etc/UTC"; };
      volumes = [
        "${path}/backups:/crafty/backups"
        "${path}/logs:/crafty/logs"
        "${path}/servers:/crafty/servers"
        "${path}/config:/crafty/app/config"
        "${path}/import:/crafty/import"
      ];
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
  networking.firewall.allowedTCPPorts = [ 30001 8123 19132 25500 ];

}
