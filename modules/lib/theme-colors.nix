# Two palettes, different provenance.
#
# `light` is hand-transcribed from pkgs.base16-schemes' horizon-light.yaml
# (Nix has no YAML parser).
#
# `dark` is NOT Horizon. It is the hand-picked palette that used to live in
# modules/home-manager/alacritty.nix, promoted to the system dark theme: pure
# black ground, warm off-white text, vivid accents. ANSI-16 has no equivalent
# for a base16 greyscale ramp, an orange, or a spare slot, so base03/base04/
# base06 are derived and base09/base0F reuse two values that were defined but
# never referenced in alacritty.nix's let block.
#
# Deliberate substitutions, so the palette survives being used for UI chrome
# rather than just terminal text: base08 takes the *bright* red #FF273F rather
# than normal #FF000F (near-pure red is punishing on borders and status bands),
# and base0E takes the *bright* magenta #6C43A5 rather than normal #FF00FF
# (pure fuchsia is unusable as a UI colour).
#
# base0D is the UI accent: bar clock, mako border, vicinae accent, lockscreen
# highlights. It is blue here, where Horizon put a pink-red.
#
# Update this file, not any hex literal elsewhere, if a palette changes.
{
  dark = {
    base00 = "000000"; # terminal background
    base01 = "222222"; # terminal normal black
    base02 = "444444"; # terminal bright black
    base03 = "6A6A6A"; # derived: continues the 00 -> 22 -> 44 ramp
    base04 = "B5B0AA"; # derived: dim foreground, warm-tinted to match base05
    base05 = "FFFAF3"; # terminal foreground
    base06 = "FFFCF8"; # derived
    base07 = "FFFFFF"; # terminal white
    base08 = "FF273F"; # terminal bright red
    base09 = "F1895C"; # the unused `orange` from alacritty.nix
    base0A = "FFB900"; # terminal yellow
    base0B = "27D796"; # terminal green
    base0C = "00D7EB"; # terminal cyan
    base0D = "008DF8"; # terminal blue - the UI accent
    base0E = "6C43A5"; # terminal bright magenta
    base0F = "E95678"; # the unused `red` from alacritty.nix
  };
  light = {
    base00 = "FDF0ED";
    base01 = "FADAD1";
    base02 = "F9CBBE";
    base03 = "BDB3B1";
    base04 = "948C8A";
    base05 = "403C3D";
    base06 = "302C2D";
    base07 = "201C1D";
    base08 = "F7939B";
    base09 = "F6661E";
    base0A = "FBE0D9";
    base0B = "94E1B0";
    base0C = "DC3318";
    base0D = "DA103F";
    base0E = "1D8991";
    base0F = "E58C92";
  };
}
