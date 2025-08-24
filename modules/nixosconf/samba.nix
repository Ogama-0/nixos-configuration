{ cfg, ... }:
let path = "${cfg.home_path}/share";
in {
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "NixOS Samba Server";
        "security" = "user";
        "map to guest" = "Bad User";
      };
      public = {
        comment = "ssd file sharing";
        browseable = "yes";
        "guest ok" = "no";
        path = path;
        "read only" = "no";
      };
    };
  };
  systemd.tmpfiles.rules = [ "d ${path}        0755 ${cfg.user} users -" ];
}
