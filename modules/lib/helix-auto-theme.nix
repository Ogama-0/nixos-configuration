# The body of ~/.config/helix/themes/auto.toml, which darkman swaps at runtime.
# Imported by modules/home-manager/helix.nix (to seed it) and by
# modules/home-manager/darkman.nix (to switch it), so these live in exactly one
# place - same reason as modules/lib/palette.nix.
#
# helix is the one app that does NOT follow the terminal's ANSI palette. It
# gets real themes instead, because term16_* only reaches for the 16 ANSI
# slots and loses all the syntax nuance a proper theme carries.
#
# dark  - Horizon dark, with the editing ground forced to pure black so it is
#         seamless with the terminal's #000000 background. Horizon's own
#         chrome colour (dark-bg #16161C, used by the statusline, popups,
#         menus and bufferline) is deliberately left alone, so those stay
#         faintly visible against the black editing area rather than
#         disappearing into it.
# light - One Light, as shipped. Note its ground is #FAFAFA, a slightly cooler
#         white than the terminal's warm #FDF0ED, so the editing area reads as
#         a subtly different shade inside the terminal.
#
# Both themes ship with helix; a name helix cannot resolve does not error, it
# logs "failed to load theme" and silently falls back to the default. Nothing
# checks that for you - this repo has no test suite - so if you change either
# name, confirm by hand that helix resolves it.
{ pkgs }:
variant:
if variant == "light" then
  pkgs.writeText "helix-auto-light.toml" ''inherits = "onelight"
''
else
  pkgs.writeText "helix-auto-dark.toml" ''inherits = "horizon-dark"
"ui.background" = { bg = "#000000" }
''
