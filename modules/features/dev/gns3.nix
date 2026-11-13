{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.dev.gns3.enable = lib.mkEnableOption "the GNS3 network simulator";
    };
in
{
  # The privileged half. GNS3 shells out to ubridge to wire a node's veth into
  # a link, which needs CAP_NET_ADMIN/CAP_NET_RAW; the wrapper is group-gated,
  # so the user has to be in `ubridge` or the exec is simply denied.
  flake.featureModules.nixos.gns3 =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.dev.gns3.enable (
        {
          users.groups.ubridge = { };

          security.wrappers.ubridge = {
            source = lib.getExe pkgs.ubridge;
            capabilities = "cap_net_raw,cap_net_admin=eip";
            owner = "root";
            group = "ubridge";
            permissions = "u=rwx,g=rx,o=r";
          };

          users.users.${config.ogama.identity.user}.extraGroups = [ "ubridge" ];
        }
      );
    };

  flake.featureModules.home.gns3 =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.dev.gns3.enable (
        {
          home.packages = with pkgs; [
            gns3-gui
            gns3-server
            dynamips
            inetutils
          ];

          # gns3-server copies its docker resources (busybox, udhcpc, init.sh)
          # out of the server package into the data dir with shutil.copy, which
          # preserves the source mode. Out of the nix store that mode is
          # r-xr-xr-x, so as soon as a gns3-server bump changes any of those
          # files the re-copy cannot truncate the old one and *every* docker
          # node start dies on EACCES -- not on anything network-shaped.
          # Put the write bit back on each switch, which is exactly when the
          # package version can change.
          home.activation.gns3DockerResources = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            resources="${config.xdg.dataHome}/GNS3/docker"
            if [ -d "$resources" ]; then
              run chmod -R u+w "$resources"
            fi
          '';
        }
      );
    };
}
