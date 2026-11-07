{ cfg, ... }:
{
  programs.nh = {
    enable = true;
    flake = "${cfg.home_path}/nixos-configuration";
  };
}
