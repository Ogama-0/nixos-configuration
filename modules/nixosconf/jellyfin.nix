{ cfg, ... }:
let path = "${cfg.home_path}/.jellyfin";
in {
  services.jellyfin = {
    enable = true;
    openFirewall = true;

    cacheDir = "${path}/cache";
    configDir = "${path}/config";
    logDir = "${path}/log";
    dataDir = "${path}/data";

    group = "users";
    user = cfg.user;

  };
  systemd.tmpfiles.rules = [
    "d ${path}          0755 ${cfg.user} users -"
    "d ${path}/cache    0755 ${cfg.user} users -"
    "d ${path}/config   0755 ${cfg.user} users -"
    "d ${path}/log      0755 ${cfg.user} users -"
    "d ${path}/data     0755 ${cfg.user} users -"
  ];

}
