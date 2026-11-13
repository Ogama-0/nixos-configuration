{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.docker.enable = lib.mkEnableOption "the docker daemon";
    };
in
{
  flake.featureModules.nixos.docker =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.docker.enable (
        {

          virtualisation.docker = {
            enable = true;
            enableOnBoot = true;

            rootless.enable = false;

            daemon.settings = {
              ipv6 = true;
              fixed-cidr-v6 = "fd00::/80";

              dns =
                [ "1.1.1.1" "8.8.8.8" "2001:4860:4860::8888" "2001:4860:4860::8844" ];
            };
          };
          networking.firewall.trustedInterfaces = [ "docker0" "podman0" ];
        }
      );
    };

  flake.featureModules.home.docker = sharedOptions;
}
