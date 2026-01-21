{ cfg, pkgs, ... }:

{
  imports = [
    ../../modules/nixosconf/docker.nix
    ../../modules/nixosconf/crafty.nix
    ../../modules/nixosconf/jellyfin.nix
    ../../modules/nixosconf/ssh.nix
    ../../modules/nixosconf/samba.nix
    ../../modules/nixosconf/joplin-server.nix
    ../../modules/nixosconf/nginx.nix
    ../../modules/nixosconf/tailscale.nix
    ../../modules/nixosconf/immich.nix
    ../../modules/nixosconf/qbittorrent.nix

    ./users
    ./nixosconf/network.nix
    ./nixosconf/backup-server.nix

    ./hardware-configuration.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  networking.hostName = "${cfg.user}host"; # Define your hostname.
  time.timeZone = "Europe/Paris";

  networking.firewall = {
    enable = true;
    allowPing = true;

  };

  environment.systemPackages = with pkgs; [ nano alsa-utils ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  environment.interactiveShellInit = ''
    exec fish
  '';

  hardware.graphics.enable = true;

  nix.settings.allowed-users = [ "@wheel" "${cfg.user}" ];

  system.stateVersion = "25.05"; # Did you read the comment?
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
