{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  networking.hostName = "ogamaNixOs"; # Define your hostname.
  time.timeZone = "Europe";

  networking.networkmanager.enable = true;

  users.users.ogama = {
    isNormalUser = true;
    extraGroups =
      [ "wheel" "networkmanager" "sway" ]; # Enable ‘sudo’ for the user.
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [ nano alsa-utils ];

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
