{ config, pkgs, ... }:

{
  imports = [
    ./_toggles.nix

    # Must be imported wherever services.postgresql runs: it unblocks
    # ensureDatabases after a glibc bump. See the module for why.
    # ../../nixosconf/qbittorrent.nix

    # Calendar stack: rustical is the CalDAV server, calendar-syncer feeds it,
    # calino is the browser client for it.

    # Not exposed by caddy.nix: its reverse proxy is added separately.
    # ../../nixosconf/crafty.nix        # <- docker

    ./_users
    ./_nixosconf/network.nix
    ./_nixosconf/backup-server.nix
    ./_nixosconf/grafana.nix

    ./_hardware-configuration.nix
  ];

  # Per-host identity, formerly host/profiles.nix's cfg-server.
  ogama.identity = {
    user = "ogama_serv";
    mail = "oscar.cornut@gmail.com";
    sshPubkey = "AAAAC3NzaC1lZDI1NTE5AAAAIHBd3Ol/Z20sasLURoDV4pHsXZ4yqmbacAYv1Uv+iyG6";
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  networking.hostName = "${config.ogama.identity.user}host"; # Define your hostname.
  time.timeZone = "Europe/Paris";

  networking.firewall = {
    enable = true;
    allowPing = true;

  };

  environment.systemPackages = with pkgs; [
    nano
    alsa-utils
  ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  hardware.graphics.enable = true;

  nix.settings.allowed-users = [
    "@wheel"
    "${config.ogama.identity.user}"
  ];

  system.stateVersion = "25.05"; # Did you read the comment?
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
