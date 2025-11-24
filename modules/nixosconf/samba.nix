{ cfg, ... }:
let
  share = cfg.server.share;

  public_path = share.public_HDD_path;
  swapsev_path = share.swapsev_path;
  time_m_path = share.Apple_save_HDD_path;
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
        "path" = public_path;
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
      "swapsev" = {
        "path" = swapsev_path;
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "yes";
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
    "d ${share.path}      0755 ${cfg.user} users -"
    "d ${swapsev_path}    0755 ${cfg.user} users -"
    "d ${public_path}     0755 ${cfg.user} users -"
    "d ${time_m_path}     0755 ${cfg.user} users -"
  ];
}
