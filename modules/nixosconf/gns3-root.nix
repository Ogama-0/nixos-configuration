{ lib, pkgs, ... }:
{
  users.groups.ubridge = { };

  security.wrappers.ubridge = {
    source = lib.getExe pkgs.ubridge;
    capabilities = "cap_net_raw,cap_net_admin=eip";
    owner = "root";
    group = "ubridge";
    permissions = "u=rwx,g=rx,o=r";
  };
}
