{ cfg, pkgs, ... }:

{
  imports = [
    ../../nixosconf/ssh.nix
    ../../nixosconf/tailscale.nix
    ../../nixosconf/samba.nix
    ../../nixosconf/avahi.nix

    ../../nixosconf/caddy.nix

    # Must be imported wherever services.postgresql runs: it unblocks
    # ensureDatabases after a glibc bump. See the module for why.
    ../../nixosconf/postgresql-collation.nix

    ../../nixosconf/jellyfin.nix
    ../../nixosconf/immich.nix
    ../../nixosconf/wakapi.nix
    # ../../nixosconf/qbittorrent.nix
    ../../nixosconf/status-page.nix

    # Calendar stack: rustical is the CalDAV server, calendar-syncer feeds it,
    # calino is the browser client for it.
    ../../nixosconf/rustical.nix
    ../../nixosconf/calendar-syncer.nix
    ../../nixosconf/calino.nix

    # Not exposed by caddy.nix: its reverse proxy is added separately.
    ../../nixosconf/la-scene-interieure.nix

    ../../nixosconf/docker.nix
    ../../nixosconf/joplin-server.nix # <- docker
    ../../nixosconf/nh.nix
    # ../../nixosconf/crafty.nix        # <- docker

    ./users
    ./nixosconf/network.nix
    ./nixosconf/backup-server.nix
    ./nixosconf/grafana.nix

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
    "${cfg.user}"
  ];

  system.stateVersion = "25.05"; # Did you read the comment?
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
