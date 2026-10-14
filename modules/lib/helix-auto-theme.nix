# The body of ~/.config/helix/themes/auto.toml, which darkman swaps at
# runtime. Imported by modules/home-manager/helix.nix (to seed it) and by
# modules/home-manager/darkman.nix (to switch it), so the term16 names live in
# exactly one place - same reason as modules/lib/alacritty-colors.nix.
#
# term16_dark / term16_light are helix's built-in themes drawn from the
# terminal's own 16 ANSI colours, so helix inherits whatever alacritty is
# currently showing rather than carrying a third copy of the palette.
{ pkgs }:
variant:
pkgs.writeText "helix-auto-${variant}.toml" ''inherits = "term16_${variant}"
''
