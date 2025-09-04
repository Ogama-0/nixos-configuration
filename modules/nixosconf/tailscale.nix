{ cfg, ... }: {
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
}
