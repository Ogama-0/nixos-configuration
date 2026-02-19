{ cfg, pkgs, ... }: {
  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [ dnsmasq ];
  networking.firewall.trustedInterfaces = [ "virbr0" ];
  virtualisation.libvirtd = {
    enable = true;
    qemu.vhostUserPackages = with pkgs; [ virtiofsd ];
  };
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable =
    true; # enable copy and paste between host and guest

  users.users.${cfg.user}.extraGroups = [ "libvirtd" ];
}
