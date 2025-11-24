{ system, config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixosconf/stream.nix
    ../../modules/nixosconf/utilities.nix
    ../../modules/nixosconf/nvidia.nix
    ../../modules/nixosconf/steam.nix
    ../../modules/nixosconf/printer.nix
    ../../modules/nixosconf/mounting.nix
    ../../modules/nixosconf/docker.nix
    ../../modules/nixosconf/tailscale.nix
    ../../modules/nixosconf/samba-cli.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  networking.hostName = "ogamaNixOs"; # Define your hostname

  networking.firewall = {
    enable = false;
    extraCommands =
      "iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns";
    # allowedTCPPorts = [ 7777 22 80 ];
    # allowedUDPPorts = [ 7777 ];
  };
  time.timeZone = "Europe/Paris";

  networking.networkmanager.enable = true;

  users.users.ogama = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "sway"
      "docker"
    ]; # Enable ‘sudo’ for the user.
  };

  environment.systemPackages = with pkgs; [ nano alsa-utils ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  security.pam.services.swaylock = { };
  security.polkit.enable = true;
  hardware.graphics.enable = true;

  environment.loginShellInit = ''
    [[ "$(tty)" == /dev/tty1 ]] && sway
  '';
  nix.settings.allowed-users = [ "@wheel" "ogama" ];

  # systemd.services.preshutdown-script = {
  #   description = "Script exécuté avant l'arrêt du système";
  #   before = [ "shutdown.target" ]; # Avant l'arrêt
  #   wantedBy = [ "shutdown.target" ]; # Exécuté lors de l'arrêt
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = ''
  #       ${pkgs.bash}/bin/bash -e ./scripts/shellscript/unmountnas.sh  && 'echo \"nas smb unmounted\" > /var/log/preshutdown.log'
  #     '';
  #     RemainAfterExit = true;
  #   };
  # };

  system.stateVersion = "24.11"; # Did you read the comment?
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
