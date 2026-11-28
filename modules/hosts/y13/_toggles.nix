{
  ogama.core = {
    nh.system.enable = true;
    ssh.enable = true;
    sh.enable = true;
    git.enable = true;
  };

  ogama.system = {
    docker.enable = true;
    samba.client.enable = true;
    tailscale.enable = true;
  };

  ogama.dev = {
    helix.enable = true;
  };

  ogama.server = {
    # caddy.enable = true; build a y13 caddy module
    # statusPage.enable = true; build a y13 status module
    # graphana.enable = true; build a y13 graphana module
    wakapi.client.enable = true;
  };

  ogama.desktop = {
    font.enable = true;
  };
}
