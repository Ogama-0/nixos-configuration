{ cfg, pkgs, ... }:

{
  imports = [
    ../../modules/nixosconf/ssh.nix
    ../../modules/nixosconf/tailscale.nix
    ../../modules/nixosconf/samba.nix
    ../../modules/nixosconf/avahi.nix

    ../../modules/nixosconf/caddy.nix

    # Must be imported wherever services.postgresql runs: it unblocks
    # ensureDatabases after a glibc bump. See the module for why.
    ../../modules/nixosconf/postgresql-collation.nix

    ../../modules/nixosconf/jellyfin.nix
    ../../modules/nixosconf/immich.nix
    ../../modules/nixosconf/wakapi.nix
    ../../modules/nixosconf/qbittorrent.nix
    ../../modules/nixosconf/status-page.nix

    # Calendar stack: rustical is the CalDAV server, calendar-syncer feeds it,
    # calino is the browser client for it.
    ../../modules/nixosconf/rustical.nix
    ../../modules/nixosconf/calendar-syncer.nix
    ../../modules/nixosconf/calino.nix

    # Not exposed by caddy.nix: its reverse proxy is added separately.
    ../../modules/nixosconf/la-scene-interieure.nix

    ../../modules/nixosconf/docker.nix
    ../../modules/nixosconf/joplin-server.nix # <- docker
    ../../modules/nixosconf/nh.nix
    # ../../modules/nixosconf/crafty.nix        # <- docker

    ./users
    ./nixosconf/network.nix
    ./nixosconf/backup-server.nix
    ./nixosconf/grafana.nix

    ./hardware-configuration.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # zfs.nix enables ZFS; its kernel module only builds against an LTS
  # kernel on this nixpkgs pin (linuxPackages_latest's zfs-kernel is
  # marked broken — see modules/nixosconf/zfs.nix).
  boot.kernelPackages = pkgs.linuxPackages;
  networking.hostName = "${cfg.user}host"; # Define your hostname.
  time.timeZone = "Europe/Paris";

  networking.firewall = {
    enable = true;
    allowPing = true;

  };

  # I have to delet this very quickly ...
  security.sudo.extraRules = [
    {
      users = [ "ogama_serv" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

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
