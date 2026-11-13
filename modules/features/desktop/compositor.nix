# Which compositor this host runs, and what "the desktop is on" means.
#
# Exactly one compositor at a time. The hyprland tree spent a long time
# unreachable precisely because it could not be imported next to sway; now both
# are always imported and the assertion is what keeps them apart.
{ ... }:
let
  sharedOptions =
    { config, lib, ... }:
    {
      options.ogama.desktop = {
        sway.enable = lib.mkEnableOption "the sway desktop";
        hyprland.enable = lib.mkEnableOption "the hyprland desktop";
        i3.enable = lib.mkEnableOption "the i3 desktop, used on the school machine";

        enable = lib.mkOption {
          type = lib.types.bool;
          default =
            config.ogama.desktop.sway.enable
            || config.ogama.desktop.hyprland.enable
            || config.ogama.desktop.i3.enable;
          defaultText = lib.literalExpression "any compositor is enabled";
          readOnly = true;
          description = ''
            Whether this host has a graphical session at all. Derived, not set:
            turn on a compositor instead.
          '';
        };
      };
    };

  assertOne =
    { config, lib, ... }:
    {
      imports = [ sharedOptions ];
      config.assertions = [
        {
          assertion =
            lib.count (x: x) [
              config.ogama.desktop.sway.enable
              config.ogama.desktop.hyprland.enable
              config.ogama.desktop.i3.enable
            ] <= 1;
          message = "ogama.desktop: enable at most one compositor (sway, hyprland or i3).";
        }
      ];
    };
in
{
  # The assertion is only meaningful where a compositor actually runs, which is
  # the Home Manager side; the NixOS side just needs the options to exist so a
  # host's _toggles.nix can set them.
  flake.featureModules.nixos.compositor = sharedOptions;
  flake.featureModules.home.compositor = assertOne;
}
