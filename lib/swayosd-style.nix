# The two SwayOSD stylesheets darkman swaps between at runtime. Imported by
# modules/features/desktop/swayosd.nix (to seed the default and point
# `stylePath` at it) and by modules/features/desktop/darkman.nix (to install
# the right one on each sunrise/sunset).
#
# The values live in lib/palette.nix under `<mode>.ui` - edit them there, not
# here. This file only renders them as GTK CSS.
#
# SwayOSD is GTK, so this is CSS and not QML @token@s, but what it draws has
# to look like it belongs to the same desktop as the notification toasts,
# because it is what replaced them for volume. Same plate colour, same
# hairline border, same green, same Orbitron numerals.
#
# Two deliberate departures from the toast:
#
#   - It is a PILL, not a rounded rectangle. A toast is something you read and
#     might act on; this is a reading that is gone in a second. The shape says
#     which one you are looking at before you have read either.
#   - No wire down the edge. The wire is the arrival gesture of something that
#     persists, and an OSD has no arrival worth narrating.
#
# Selectors are the ones SwayOSD's own stylesheet uses
# (`$out/etc/xdg/swayosd/style.css`): `window#osd` wraps `#container`, which
# holds an image and either a `progressbar` (trough + progress) or, for
# discrete steps, a `segmentedprogress` of `segment`s. Styling anything else
# is guesswork against a GTK widget tree that is not ours.
#
# `alpha()` is GTK CSS's own, which is why nothing here parses a hex string
# into channels.
{ pkgs }:
let
  palette = import ./palette.nix;

  render =
    variant:
    let
      ui = palette.${variant}.ui;

      # Near-opaque, for the reason the control panel sheet is: at 80% a
      # bright window underneath reads straight through and sits behind the
      # numerals. Same alpha and same slot as the panel's @sheetBg@, so the
      # pill and the notification plate are literally the same surface.
      #
      # Derived, not written out. Both values used to be hand-transcribed
      # hex (`rgba(253, 240, 237, 0.95)` is base00 light in decimal), which
      # is exactly the duplication the header above tells you not to make:
      # a base00 edit would have moved the whole desktop and left the OSD
      # behind. GTK's own alpha() does the compositing.
      plate = "alpha(${ui.base00}, ${if variant == "light" then "0.95" else "0.94"})";

      ink = ui.base05;

      # The same green as the toast wire - and for the same reason it is
      # `accentLine` and not base0B. This is a 4px bar on the plate, not a
      # filled badge: light's base0B against this ground measures 1.02:1
      # with the trough below, which is to say the level was not readable at
      # all. See lib/palette.nix.
      accent = palette.${variant}.accentLine;
    in
    ''
      /* Generated from lib/palette.nix (${variant}) by lib/swayosd-style.nix.
         Do NOT edit by hand: darkman overwrites this file on every switch. */

      window#osd {
        /* A pill, where a toast is a rounded rectangle. */
        border-radius: 999px;
        border: 1px solid alpha(${ink}, 0.35);
        background: ${plate};
        /* Narrower than stock, so it reads as a readout and not a dialog. */
        min-width: 220px;
      }

      window#osd #container {
        margin: 13px 18px;
      }

      window#osd image,
      window#osd label {
        color: ${ink};
      }

      /* The numerals, in the face the panel clock uses. Everything on this
         desktop that prints a number prints it in Orbitron. */
      window#osd label {
        font-family: "Orbitron", monospace;
        font-size: 0.95em;
        font-weight: 600;
      }

      /* Disabled is how SwayOSD draws MUTED. Dimming the glyph and the bar
         together is the whole mute affordance - there is no separate state. */
      window#osd progressbar:disabled,
      window#osd image:disabled {
        opacity: 0.45;
      }

      window#osd progressbar,
      window#osd segmentedprogress {
        min-height: 4px;
        border-radius: 999px;
        background: transparent;
        border: none;
      }

      window#osd trough,
      window#osd segment {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        /* The ink it is already using, faint: a trough is "the bar,
           unfilled", not a colour of its own. */
        background: alpha(${ink}, 0.2);
      }

      window#osd progress,
      window#osd segment.active {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: ${accent};
      }

      window#osd segment {
        margin-left: 6px;
      }

      window#osd segment:first-child {
        margin-left: 0;
      }
    '';
in
{
  dark = pkgs.writeText "swayosd-dark.css" (render "dark");
  light = pkgs.writeText "swayosd-light.css" (render "light");
}
