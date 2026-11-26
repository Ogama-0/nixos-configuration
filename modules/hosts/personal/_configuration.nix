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

    ./_nixosconf/backup-laptop.nix
    ./_nixosconf/asus-numpad.nix
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
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # https://discussion.fedoraproject.org/t/nvme-i-o-timeouts-and-slow-boot-on-asus-zenbook-with-micron-mtfdkba1t0qgn/187890
    # I desactivate the Intel VMD in the UEFI

    supportedFilesystems = [ "ntfs" ];
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  networking.hostName = "ogamaNixOs-zenbook"; # Define your hostname
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
    helix
    alsa-utils
    libva-utils # vainfo, the only way to check the VA-API stack is actually live
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
  # Arrow Lake-P / Arc 140T (Xe2). `hardware.graphics.enable` alone ships only
  # Mesa, which carries no VA-API driver for Intel — /run/opengl-driver/lib/dri
  # ends up holding the radeonsi/nouveau/d3d12 `*_drv_video.so` and nothing
  # else, so every browser silently decodes video on the CPU. iHD is what puts
  # H.264/VP9/AV1 back on the media engine.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # iHD, the VA-API driver itself
      vpl-gpu-rt # oneVPL runtime, for anything that asks through libvpl
    ];
  };

  # libva autodetects a driver from the kernel driver name, which is `xe` on
  # this generation and maps to nothing, so iHD has to be named explicitly.
  # System-wide rather than per-app: ffmpeg and mpv want it as much as Zen.
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # environment.loginShellInit = ''
  #   [[ "$(tty)" == /dev/tty1 ]]
  # '';

  nix.settings.allowed-users = [
    "@wheel"
    "ogama"
  ];

  system.stateVersion = "26.05"; # Did you read the comment?
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
