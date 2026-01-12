{ cfg, ... }:
let
  headscale-port = 3006;
  headscale-derp-port = 3478;
  headscale-hostname = "headscale.{cfg.server.domain}";
  headscale-metrics-port = 9003;
in {
  networking.firewall.allowedUDPPorts = [ headscale-derp-port ];
  services.headscale = {
    enable = true;
    port = 8090;
    settings = {
      server_url = "https://${headscale-hostname}";
      metrics_listen_addr = "127.0.0.1:${toString headscale-metrics-port}";
    };
    # TODO
  };

}
