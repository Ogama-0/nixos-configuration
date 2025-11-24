{ pkgs, cfg, ... }: {
  environment.systemPackages = [ pkgs.cifs-utils pkgs.samba ];

  fileSystems."${cfg.share.path}/swapsev" = {
    device = "//ogamaservhost/swapsev";
    fsType = "cifs";
    options = let
      # this line prevents hanging on network split
      automount_opts =
        "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";

    in [
      "${automount_opts},credentials=/etc/nixos/smb-secrets,uid=1000,gid=100"
    ];
  };
  fileSystems."${cfg.share.path}/public" = {
    device = "//ogamaservhost/public";
    fsType = "cifs";
    options = let
      # this line prevents hanging on network split
      automount_opts =
        "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";

    in [
      "${automount_opts},credentials=/etc/nixos/smb-secrets,uid=1000,gid=100"
    ];
  };
}
