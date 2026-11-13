{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.headscale.enable = lib.mkEnableOption "the headscale coordination server";
    };
in
{
  flake.featureModules.nixos.headscale =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.server.headscale.enable (
        let
          headscale-port = 3006;
          headscale-derp-port = 3478;
          headscale-hostname = "headscale.{config.ogama.server.domain}";
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
      );
    };

  flake.featureModules.home.headscale = sharedOptions;
}
