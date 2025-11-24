{ pkgs, cfg, ... }:
let
  share = cfg.cfg-server.share;
  public_path = share.public_HDD_path;
  swapsev_path = share.swapsev_path;
in {
  environment.systemPackages = [ pkgs.cifs-utils ];

  fileSystems."${cfg.home_path}/swapsev" = {
    device = "//ogamaservhost/${swapsev_path}/";
    fsType = "cifs";
    options = let
      # this line prevents hanging on network split
      automount_opts =
        "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";

    in [ "${automount_opts},credentials=/etc/nixos/smb-secrets" ];
  };
  fileSystems."${cfg.share.path}/public" = {
    device = "//ogamaservhost/${public_path}/";
    fsType = "cifs";
    options = let
      # this line prevents hanging on network split
      automount_opts =
        "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";

    in [ "${automount_opts},credentials=/etc/nixos/smb-secrets" ];
  };
}
