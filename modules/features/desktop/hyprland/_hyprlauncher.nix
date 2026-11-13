# Part of the hyprland feature, which imports this unconditionally —
# imports instruct the module system and cannot be conditional — so the
# gate lives here.
{ lib, config, upkgs, ... }:
{
  config = lib.mkIf config.ogama.desktop.hyprland.enable (
    {

      home.packages = [ upkgs.hyprlauncher ];
    }
  );
}
