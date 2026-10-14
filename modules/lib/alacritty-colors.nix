# The two alacritty colour files darkman swaps between at runtime. Imported by
# modules/home-manager/alacritty.nix (to seed the default and declare the
# import) and by modules/home-manager/darkman.nix (to install the right one on
# each sunrise/sunset).
#
# `dark` is this machine's long-standing hand-picked palette, preserved
# verbatim. modules/lib/theme-colors.nix' dark palette was derived FROM these
# values, but deliberately drops normal red (#ff000f) and normal magenta
# (#FF00FF) as too harsh for UI chrome - the terminal keeps its full original
# ANSI set, so this is written out rather than generated from base16.
#
# `light` keeps Horizon light's background and foreground but uses hand-tuned
# ANSI accents. The naive base16 mapping is unusable: base0A ("yellow") is
# #FBE0D9, which measures 1.13:1 against the #FDF0ED ground - invisible - while
# base0D ("blue") is a crimson and base0C ("cyan") a red-orange, so both would
# read red. Every value below was measured against #FDF0ED and clears the 4.5:1
# text floor; ratios are in the comments. "Bright" is *darker* here, because on
# a light ground more emphasis means more contrast.
#
# Light cyan is #15666C, not the #1D8991 used for the status widget's light
# upColor: that value is a filled band against a 3:1 floor and measures only
# 3.74:1 as text. Same hue, different floor - not an inconsistency.
{ pkgs }:
{
  dark = pkgs.writeText "alacritty-colors-dark.toml" ''
    [colors.primary]
    background = "#000000"
    foreground = "#fffaf3"

    [colors.normal]
    black   = "#222222"
    red     = "#ff000f"
    green   = "#27d796"
    yellow  = "#ffb900"
    blue    = "#008df8"
    magenta = "#FF00FF"
    cyan    = "#00d7eb"
    white   = "#ffffff"

    [colors.bright]
    black   = "#444444"
    red     = "#ff273f"
    green   = "#abe05a"
    yellow  = "#ffd141"
    blue    = "#0092ff"
    magenta = "#6c43a5"
    cyan    = "#67ffef"
    white   = "#ffffff"
  '';

  light = pkgs.writeText "alacritty-colors-light.toml" ''
    [colors.primary]
    background = "#FDF0ED"
    foreground = "#2B2728"  # 13.3:1

    [colors.normal]
    black   = "#1A1618"  # 16.1:1
    red     = "#991026"  #  7.7:1
    green   = "#14532D"  #  8.2:1
    yellow  = "#6B4A00"  #  7.2:1
    blue    = "#0B3D91"  #  9.0:1
    magenta = "#6B2585"  #  8.5:1
    cyan    = "#0B4F56"  #  8.3:1
    white   = "#403C3D"  #  9.8:1

    [colors.bright]
    black   = "#5A5456"  #  6.7:1 - comments; muted on purpose, so it is the
                         #          one slot deliberately below the 7:1 floor
    red     = "#7A0C1E"  #  9.9:1
    green   = "#0D3A1F"  # 11.5:1
    yellow  = "#4F3600"  # 10.1:1
    blue    = "#072C6B"  # 11.9:1
    magenta = "#4E1B61"  # 11.4:1
    cyan    = "#073A3F"  # 11.2:1
    white   = "#1A1618"  # 16.1:1
  '';
}
