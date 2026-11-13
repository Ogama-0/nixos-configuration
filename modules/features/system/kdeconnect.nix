{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.kdeconnect.enable = lib.mkEnableOption "KDE Connect, which the messages panel talks to";
    };
in
{
  flake.featureModules.nixos.kdeconnect =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.kdeconnect.enable (
        {
          # Phone link for the panel's Mobile zone
          # (quickshell/components/panel/MobileModel.qml).
          #
          # The NixOS option rather than just the package: pairing needs TCP and UDP
          # 1714-1764 open, and a paired phone that cannot reach the daemon looks
          # exactly like no phone at all.
          programs.kdeconnect = {
            enable = true;
            package = pkgs.kdePackages.kdeconnect-kde;
          };
        }
      );
    };

  flake.featureModules.home.kdeconnect = sharedOptions;
}
