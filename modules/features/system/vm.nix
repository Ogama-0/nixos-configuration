{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.vm.enable = lib.mkEnableOption "libvirt and QEMU virtualisation";
    };
in
{
  flake.featureModules.nixos.vm =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.vm.enable (
        {
          programs.virt-manager.enable = true;

          environment.systemPackages = with pkgs; [ dnsmasq ];
          networking.firewall.trustedInterfaces = [ "virbr0" ];
          virtualisation.libvirtd = {
            enable = true;
            qemu.vhostUserPackages = with pkgs; [ virtiofsd ];
          };
          services.qemuGuest.enable = true;
          services.spice-vdagentd.enable = true; # enable copy and paste between host and guest

          users.users.${config.ogama.identity.user}.extraGroups = [ "libvirtd" ];
        }
      );
    };

  flake.featureModules.home.vm = sharedOptions;
}
