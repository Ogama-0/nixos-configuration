{ pkgs, cfg, ... }:
let
  public_path = cfg.cfg-server.share.public_HDD_path;
  apple_path = cfg.cfg-server.share.Apple_save_HDD_path;
  tmp_path = cfg.cfg-server.server.share.temp_path;
in {
  environment.systemPackages = [ pkgs.cifs-utils ];

  fileSystems."${cfg.home_path}/swapsev" = {
    device = "//ogamaservhost/${tmp_path}/";
    fsType = "cifs";
    options = let
      # this line prevents hanging on network split
      automount_opts =
        "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";

    in [ "${automount_opts},credentials=/etc/nixos/smb-secrets" ];
  };
}
