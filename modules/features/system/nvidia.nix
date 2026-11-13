{ ... }:
let
  # Needs the LTS kernel: pinning linuxPackages_latest makes this fail to compile and fall out of the binary cache.
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.nvidia.enable = lib.mkEnableOption "the nvidia-open driver";
    };
in
{
  flake.featureModules.nixos.nvidia =
    { config, lib, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.nvidia.enable (
        {
          # Pilotes graphiques
          boot.kernelModules = [
            "nvidia"
            "nvidia-drm"
          ];
          boot.kernelParams = [
            "modprobe.blacklist=nouveau,nova_core,nvidiafb"
            "nvidia-drm.modeset=1"
          ];
          services.xserver.videoDrivers = [
            "nvidia"
            "modesetting"
          ];

          hardware.nvidia = {
            modesetting.enable = true;

            open = true; # j'ai vu sur https://nixos.wiki/wiki/nvidia que ils conseillais de mettre a true pour les laptop RTX 20XX +

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

          # The nvidia-open module only builds (and is only cached by hydra) against
          # the default LTS kernel: 595.71.05 fails to compile on 7.3 (implicit
          # strncpy), and no 7.x/driver combination is prebuilt. Hence the LTS default
          # rather than _latest or a version pin that goes EOL every few months.
          boot.kernelPackages = pkgs.linuxPackages;
          hardware.graphics = {
            enable = true;
            enable32Bit = true;
          };
        }
      );
    };

  flake.featureModules.home.nvidia = sharedOptions;
}
