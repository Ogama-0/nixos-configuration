{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.core.ssh.enable = lib.mkEnableOption "the SSH daemon and its authorized keys";
    };
in
{
  flake.featureModules.nixos.ssh =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.core.ssh.enable (
        {
          services.openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = false;
              PermitRootLogin = "no";
            };
          };

          programs.ssh.knownHosts = {
            ogamaNixos.publicKey =
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILaKjKo1kaGVYdA5U6kvrjhDj1T3tp04CmiZE3YmA7id ogama@nixos";

            ogamaWindows.publicKey =
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINrLqqiHHp3wkHftN6dvbpdPB69L/w44yJ61tuMPa6TI ogama@DESKTOP-AM3K31V";
          };

          networking.firewall.allowedTCPPorts = [ 22 ];
        }
      );
    };

  flake.featureModules.home.ssh = sharedOptions;
}
