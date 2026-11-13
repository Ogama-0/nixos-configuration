{ config, ... }:
{
  programs.nh = {
    enable = true;
    flake = "${config.ogama.identity.homePath}/nixos-configuration";
  };
}
