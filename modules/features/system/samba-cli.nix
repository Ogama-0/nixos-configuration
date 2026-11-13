{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.sambaCli.enable = lib.mkEnableOption "client mounts of the server's Samba shares";
    };
in
{
  flake.featureModules.nixos.sambaCli =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.sambaCli.enable (
        {
          environment.systemPackages = [ pkgs.cifs-utils pkgs.samba ];

          fileSystems."${config.ogama.share.path}/swapsev" = {
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
          fileSystems."${config.ogama.share.path}/public" = {
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
      );
    };

  flake.featureModules.home.sambaCli = sharedOptions;
}
