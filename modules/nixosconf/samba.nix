{ cfg, ... }:
let
  path = "${cfg.home_path}/share";
  path_prv = "${path}/Private";
  path_pub = "${path}/Public";
in {
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "smbnix";
        "netbios name" = "smbnix";
        "security" = "user";
        #"use sendfile" = "yes";
        #"max protocol" = "smb2";
        # note: localhost is the ipv6 localhost ::1
        "hosts allow" = "192.168.1.0/24 127.0.0.1 localhost 100.0.0.0/8";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      "public" = {
        "path" = path_pub;
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
      "private" = {
        "path" = path_prv;
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
    };
  };
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
  services.gvfs.enable = true;
  systemd.tmpfiles.rules = [
    "d ${path}        0755 ${cfg.user} users -"
    "d ${path_prv}    0755 ${cfg.user} users -"
    "d ${path_pub}    0755 ${cfg.user} users -"
  ];
}
