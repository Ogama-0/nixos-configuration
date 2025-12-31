{ config, lib, pkgs, ... }:

{
  # Pilotes graphiques
  boot.kernelModules = [ "nvidia" "nvidia-drm" ];
  boot.kernelParams =
    [ "modprobe.blacklist=nouveau,nova_core,nvidiafb" "nvidia-drm.modeset=1" ];
  services.xserver.videoDrivers = [ "nvidia" "modesetting" ];

  hardware.nvidia = {
    modesetting.enable = true;

    open =
      true; # j'ai vu sur https://nixos.wiki/wiki/nvidia que ils conseillais de mettre a true pour les laptop RTX 20XX +

    nvidiaSettings = true;

    powerManagement.enable = false;
    powerManagement.finegrained = false;

    prime = {
      sync.enable = true;
      amdgpuBusId = lib.mkForce "PCI:5:0:0";
      nvidiaBusId = lib.mkForce "PCI:1:0:0";
    };

    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
