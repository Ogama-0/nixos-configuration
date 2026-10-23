# THE place to change colours. Everything that switches with darkman derives
# from this file, and every value here is a plain `#RRGGBB` you can paste
# straight out of a colour picker.
#
# What reads this:
#   ui       -> the quickshell bar, widgets and lockscreen, the greeter, mako,
#               and vicinae, via modules/lib/theme-colors.nix
#   terminal -> alacritty, via modules/lib/alacritty-colors.nix - and through
#               alacritty, most TUI apps (bat, yazi, ...) since they draw with
#               the terminal's own ANSI colours. helix is the exception: it
#               uses real themes instead, see modules/lib/helix-auto-theme.nix
#   status   -> the oserv status widget, via the quickshell module
#   both     -> zellij, via modules/lib/zellij-theme.nix - it needs its own
#               themes because it paints its chrome in true colour instead of
#               the terminal's ANSI slots, and it takes the ground from `ui`
#               but the light accents from `terminal` (reasons in that file)
#
# Two things NOT to change casually:
#   * `ui` follows the base16 slot convention (base00 darkest ground ->
#     base07 lightest text, base08-base0F accents). Consumers assume those
#     roles; swapping a slot's role rather than its value will look wrong.
#   * The light values were measured for contrast against their own grounds,
#     to a >= 7:1 (WCAG AAA) floor for `light.terminal`. NOTHING ENFORCES
#     THAT: the ratios in the comments below were computed by hand when the
#     values were picked, and this repo has no test suite to re-check them
#     (see tests/laserbar/README.md). A low-contrast pick here ships
#     silently, so re-measure by hand when you change one.
#
# Not covered here: the swaylock module keeps its own hardcoded colours and
# does not switch with darkman.
{
  dark = {
    # NOT Horizon. This is the hand-picked terminal palette promoted to the
    # system dark theme: pure black ground, warm off-white text, vivid accents.
    # base03/base04/base06 are derived (ANSI-16 has no greyscale ramp), and
    # base09/base0F reuse two values that were defined but unused in the old
    # alacritty.nix. base08 takes the *bright* red and base0E the *bright*
    # magenta, because normal #ff000f and #FF00FF are punishing as UI chrome.
    ui = {
      base00 = "#000000"; # background
      base01 = "#222222"; # lighter background (status bars, line numbers)
      base02 = "#444444"; # selection background
      base03 = "#6A6A6A"; # comments, invisibles
      base04 = "#B5B0AA"; # dark foreground (muted text)
      base05 = "#FFFAF3"; # default foreground
      base06 = "#FFFCF8"; # light foreground
      base07 = "#FFFFFF"; # lightest
      base08 = "#FF273F"; # red
      base09 = "#F1895C"; # orange
      base0A = "#FFB900"; # yellow
      base0B = "#27D796"; # green
      base0C = "#00D7EB"; # cyan
      base0D = "#008DF8";
      # blue - THE UI ACCENT (bar clock, mako border,
      #        vicinae accent, lockscreen highlights)
      base0E = "#6C43A5"; # magenta
      base0F = "#E95678"; # spare / pink
    };

    # The terminal keeps its full original ANSI set, including the harsh
    # normal red and magenta that `ui` deliberately drops.
    terminal = {
      background = "#000000";
      foreground = "#fffaf3";
      normal = {
        black = "#222222";
        red = "#ff000f";
        green = "#27d796";
        yellow = "#ffb900";
        blue = "#008df8";
        magenta = "#FF00FF";
        cyan = "#00d7eb";
        white = "#ffffff";
      };
      bright = {
        black = "#444444";
        red = "#ff273f";
        green = "#abe05a";
        yellow = "#ffd141";
        blue = "#0092ff";
        magenta = "#6c43a5";
        cyan = "#67ffef";
        white = "#ffffff";
      };
    };

    # Status-widget semantics. Measured against the composited panel ground -
    # base00 is pure black, so the worst case (a white wallpaper through 10%,
    # about #1A1A1A) still clears every floor: 3:1 for a filled band, 4.5:1
    # for the 11px latency column.
    status = {
      up = "#00D7EB"; # cyan,   9.9:1
      degraded = "#F1895C"; # orange, 7.0:1
      down = "#FF273F"; # red,    4.7:1
      muted = "#B5B0AA"; # 8.1:1
    };
  };

  light = {
    # Horizon light, hand-transcribed from pkgs.base16-schemes' horizon-light.yaml.
    ui = {
      base00 = "#FDF0ED";
      base01 = "#FADAD1";
      base02 = "#F9CBBE";
      base03 = "#BDB3B1";
      base04 = "#948C8A";
      base05 = "#403C3D";
      base06 = "#302C2D";
      base07 = "#201C1D";
      base08 = "#F7939B";
      base09 = "#F6661E";
      base0A = "#FBE0D9";
      base0B = "#94E1B0";
      base0C = "#DC3318";
      base0D = "#DA103F";
      base0E = "#1D8991";
      base0F = "#E58C92";
    };

    # Horizon light's ground and text, but hand-tuned ANSI accents: the raw
    # base16 slots are unusable as a terminal palette (base0A "yellow" is
    # #FBE0D9, a measured 1.13:1 against the background - invisible - while
    # base0D "blue" is a crimson and base0C "cyan" a red-orange).
    #
    # Every value below clears 7:1 (WCAG AAA) against #FDF0ED; the ratios are
    # measured rather than estimated, but measured by hand and unenforced -
    # see the header. "Bright" is *darker* here, because on a light ground
    # more emphasis means more contrast.
    terminal = {
      background = "#FDF0ED";
      foreground = "#2B2728"; # 13.3:1
      normal = {
        black = "#1A1618"; # 16.1:1
        red = "#991026"; # 7.7:1
        green = "#14532D"; # 8.2:1
        yellow = "#6B4A00"; # 7.2:1
        blue = "#0B3D91"; # 9.0:1
        magenta = "#6B2585"; # 8.5:1
        cyan = "#0B4F56"; # 8.3:1
        white = "#403C3D"; # 9.8:1
      };
      bright = {
        black = "#5A5456";
        #  6.7:1 - comments; muted on purpose, the one
        #          slot deliberately below the 7:1 floor
        red = "#7A0C1E"; # 9.9:1
        green = "#0D3A1F"; # 11.5:1
        yellow = "#4F3600"; # 10.1:1
        blue = "#072C6B"; # 11.9:1
        magenta = "#4E1B61"; # 11.4:1
        cyan = "#073A3F"; # 11.2:1
        white = "#1A1618"; # 16.1:1
      };
    };

    # Measured against the composited light panel ground (#EBDFDC). These are
    # NOT the matching base16 slots: Horizon light puts teal at base0E and a
    # red-orange at base0C, and several slots fail their floors outright.
    status = {
      up = "#1D8991"; # the darker teal, clears 3:1 as a filled band
      degraded = "#C2490B"; # base09 #F6661E is only 2.4:1; darkened to 3.8:1
      down = "#DA103F";
      muted = "#403C3D";
      # base04 is 2.5:1 at 11px; this is base05, 4.9:1
      # at the 80% alpha the widget applies
    };
  };
}
