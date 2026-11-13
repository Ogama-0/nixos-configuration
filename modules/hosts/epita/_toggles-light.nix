# epita-light: the same machine, trimmed so it rebuilds faster.
#
# Everything epita turns on, minus the pieces that cost the most to build, plus
# kitty in place of alacritty. This used to be a second near-identical imports
# list, where the difference between the two profiles could only be found by
# diffing them.
{ lib, ... }:
{
  imports = [ ./_toggles.nix ];

  ogama.dev = {
    vim.enable = lib.mkForce false;
    zellij.enable = lib.mkForce false;
    epitaTools.enable = lib.mkForce false;
  };

  ogama.desktop = {
    alacritty.enable = lib.mkForce false;
    gtk.enable = lib.mkForce false;
    kitty.enable = lib.mkForce true;
  };
}
