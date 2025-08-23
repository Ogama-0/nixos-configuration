{ cfg, pkgs, ... }:

{
  imports = [
    ../modules/nixosconf/docker.nix
    ../modules/nixosconf/crafty.nix
    ../modules/nixosconf/jellyfin.nix
    ../modules/nixosconf/ssh.nix

  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "${cfg.user}host"; # Define your hostname.
  time.timeZone = "Europe/Paris";

  networking.networkmanager = { enable = true; };

  users.users.ogama_serv = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ]; # Enable ‘sudo’ for the user.
  };

  environment.systemPackages = with pkgs; [ nano alsa-utils ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  hardware.graphics.enable = true;
  environment.loginShellInit =
    ''echo" Bonjour dans le serveur de ${cfg.user}Prime"  '';
  nix.settings.allowed-users = [ "@wheel" "${cfg.user}" ];

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

  system.stateVersion = "25.05"; # Did you read the comment?
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
