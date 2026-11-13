{
  system,
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./_toggles.nix
    ./_hardware-configuration.nix
    ../../nixosconf/stream.nix
    ../../nixosconf/nvidia.nix
    ../../nixosconf/geoclue.nix
    ../../nixosconf/kdeconnect.nix
    ../../nixosconf/steam.nix
    ../../nixosconf/printer.nix
    ../../nixosconf/mounting.nix
    ../../nixosconf/docker.nix
    ../../nixosconf/tailscale.nix
    ../../nixosconf/samba-cli.nix
    ../../nixosconf/gtklock
    ../../nixosconf/greetd.nix
    ../../nixosconf/vm.nix
    ../../nixosconf/localsend.nix
    ../../nixosconf/earlyoom.nix
    ../../nixosconf/gns3-root.nix

    ./_nixosconf/backup-laptop.nix
    ./_nixosconf/volumes.nix
  ];

  # Per-host identity. These were entries in host/profiles.nix, reached through
  # a `cfg` attrset in specialArgs; they are declared options now
  # (modules/features/core/shared-options.nix) and set here, by the host they
  # describe.
  ogama.identity = {
    user = "ogama";
    sshPubkey = "AAAAC3NzaC1lZDI1NTE5AAAAILaKjKo1kaGVYdA5U6kvrjhDj1T3tp04CmiZE3YmA7id";
  };

  # Use the systemd-boot EFI boot loader.
  boot = {
    # Keep amdgpu's post-resume register-retry warnings (a known upstream
    # bug on Cezanne/Renoir APUs) out of the framebuffer during lid-open;
    # they still land in `journalctl -k` at this level.
    consoleLogLevel = 3;

    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # kernelPackages = pkgs.linuxPackages_latest;
    supportedFilesystems = [ "ntfs" ];
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  networking.hostName = "ogamaNixOs"; # Define your hostname

  networking.firewall = {
    enable = false;
    extraCommands = "iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns";
    allowedTCPPorts = [ 7777 ];
    allowedUDPPorts = [ 7777 ];
  };
  # time.timeZone = "America/Monterrey";
  # time.timeZone = "America/Mazatlan"; # Los Cabos
  time.timeZone = "Europe/Paris";

  services.resolved.enable = true;
  networking.networkmanager.enable = true;
  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
    "4.4.4.4"
  ];

  users.users.ogama = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "sway"
      "docker"
    ]; # Enable ‘sudo’ for the user.
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

  security.pam.services.swaylock = { };
  security.pam.services.quickshell-lock = { };
  security.polkit.enable = true;
  hardware.graphics.enable = true;

  # environment.loginShellInit = ''
  #   [[ "$(tty)" == /dev/tty1 ]]
  # '';

  nix.settings.allowed-users = [
    "@wheel"
    "ogama"
  ];

  system.stateVersion = "24.11"; # Did you read the comment?
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
