{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./stream.nix
    # ./systemconf/wireguard.nix ]; 

  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # enable for wireguard 
  boot.kernel.sysctl = { "net.ipv4.ip_forward" = "1"; };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  networking.hostName = "ogamaNixOs"; # Define your hostname.
  time.timeZone = "Europe/Paris";

  networking.networkmanager.enable = true;

  users.users.ogama = {
    isNormalUser = true;
    extraGroups =
      [ "wheel" "networkmanager" "sway" ]; # Enable ‘sudo’ for the user.
  };

  environment.systemPackages = with pkgs; [ nano alsa-utils ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  services.upower.enable = true;

  security.pam.services.swaylock = { };
  security.polkit.enable = true;
  hardware.graphics.enable = true;
  environment.loginShellInit = ''
    [[ "$(tty)" == /dev/tty1 ]] && sway
  '';
  nix.settings.allowed-users = [ "@wheel" "ogama" ];

  system.stateVersion = "24.11"; # Did you read the comment?
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
