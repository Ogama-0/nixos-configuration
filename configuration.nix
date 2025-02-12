{ config, lib, pkgs, ... }:

{
  imports =
    [ 
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "ogamaNixOs"; # Define your hostname.
  time.timeZone = "Europe";

  networking.networkmanager.enable = true;

  

  # Configure keymap in X11
  services.xserver.xkb.layout = "us";

    users.users.ogama = {
    isNormalUser = true;
    description = "bonjour a tous";
    extraGroups = [ "wheel" "networkmanager" ]; # Enable ‘sudo’ for the user.
    shell = pkgs.bash;
    home = "/home/ogama";
    };

   nixpkgs.config.allowUnfree = true; 

  environment.systemPackages = with pkgs; [ 
    
  nano 
  helix 
  jetbrains-toolbox
    
  wlroots 

  wireguard-tools
  vesktop  
  tlrc
  git
  acpi      
    ];

  services.upower.enable = true;
  
  programs.sway = {
    enable = true;
   };
  programs.xwayland.enable = true;
  
  security.polkit.enable = true;
  programs.firefox.enable = true;


  nix.settings.allowed-users = [
    "@wheel"
    "ogama"
    ];
    
 system.stateVersion = "24.11"; # Did you read the comment?
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
