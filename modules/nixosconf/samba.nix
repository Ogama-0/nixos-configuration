{ cfg, pkgs, config, lib, ... }:
let

  share = cfg.path.hdd.share;
  public_path = cfg.path.hdd.share.public_HDD_path;
  swapsev_path = cfg.path.ssd.share.swapsev_path;
  time_m_path = cfg.path.hdd.share.Apple_save_HDD_path;

  # Authenticated Samba-only accounts (no shell login). Passwords live in
  # sops/oserv.yaml under "samba_<user>_password" and are pushed into
  # Samba's own password database (tdbsam) via smbpasswd, since it's
  # separate from the Unix account password.
  sambaUsers = [ "leoniecornut" "nicolascornut" ];
in {
  sops.secrets = lib.listToAttrs (map (u:
    lib.nameValuePair "samba_${u}_password" {
      sopsFile = ../../sops/oserv.yaml;
      # re-runs the smbpasswd unit whenever this secret's content changes
      restartUnits = [ "samba-set-${u}-password.service" ];
    }) sambaUsers);

  users.groups = lib.listToAttrs (map (u: lib.nameValuePair u { }) sambaUsers);
  users.users = lib.listToAttrs (map (u:
    lib.nameValuePair u {
      isSystemUser = true;
      group = u;
      description = "Samba-only account (no shell login)";
    }) sambaUsers);

  systemd.services = lib.listToAttrs (map (u:
    lib.nameValuePair "samba-set-${u}-password" {
      description = "Set Samba password for ${u} from sops secret";
      wantedBy = [ "multi-user.target" ];
      before = [ "samba-smbd.service" ];
      after = [ "sops-install-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        pass=$(cat ${config.sops.secrets."samba_${u}_password".path})
        printf '%s\n%s\n' "$pass" "$pass" | ${pkgs.samba}/bin/smbpasswd -s -a ${u}
      '';
    }) sambaUsers);

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

        # macOS/Time Machine compatibility (AAPL extensions, resource forks)
        "vfs objects" = "catia fruit streams_xattr full_audit";
        "fruit:aapl" = "yes";

        # auth_audit gives clean auth success/failure entries without the
        # volume of a full file-operation audit.
        "log level" = "1 auth_audit:3";

        # full_audit logs only connect/disconnect (not file operations) via
        # syslog under identifier "smbd_audit", landing in the systemd
        # journal tagged with the real share name (%S resolves correctly
        # here, unlike in "log file" above — full_audit runs with an actual
        # connection context). alloy-config.alloy filters on that identifier
        # and extracts a "share" label from the "%S|%U|%I" prefix.
        "full_audit:prefix" = "%S|%U|%I";
        "full_audit:success" = "connect disconnect";
        "full_audit:failure" = "connect disconnect";
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
      "timemachine" = {
        "path" = time_m_path;
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        # authenticated users (leoniecornut, nicolascornut, ...) only belong
        # to their own private group, so without forcing ownership they'd
        # hit the directory's "other" bits (r-x, no write) as ogama_serv:users
        "force user" = cfg.user;
        "force group" = "users";
        "fruit:time machine" = "yes";
        "fruit:time machine max size" = "500G";
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
    "d /var/log/samba     0755 root root -"
  ];
}
