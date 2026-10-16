#!/usr/bin/env bash
# Assert something about a region of a rendered bar.
#
#   laserbar-probe.sh <png> <x> <y> <w> <h> --near '#rrggbb' [tolerance=24]
#   laserbar-probe.sh <png> <x> <y> <w> <h> --dominant r|g|b [margin=18]
#
# A region average, not a single pixel: the beam carries animated wave strands
# and a white core line straight down its centre, so any one pixel is a coin
# toss. The average over a block is stable across frames.
#
# --near is for flat areas - a capsule fill, an outline, a knockout glyph.
# --dominant is for the beam, where the honest assertion is "this stretch
# reads green" rather than an exact value the strands never quite hit.
set -euo pipefail

PNG="${1:?usage: laserbar-probe.sh <png> <x> <y> <w> <h> --near|--dominant ...}"
X="${2:?}"; Y="${3:?}"; W="${4:?}"; H="${5:?}"; MODE="${6:?}"
[ -f "$PNG" ] || { echo "no such png: $PNG" >&2; exit 2; }

magick_cmd() {
    if command -v magick >/dev/null 2>&1; then
        magick "$@"
    else
        nix shell nixpkgs#imagemagick --command magick "$@"
    fi
}

read -r R G B <<<"$(magick_cmd "$PNG" -crop "${W}x${H}+${X}+${Y}" +repage \
    -resize 1x1\! -depth 8 -format '%[fx:int(255*r)] %[fx:int(255*g)] %[fx:int(255*b)]' info:)"

printf 'region %sx%s+%s+%s average: #%02x%02x%02x\n' "$W" "$H" "$X" "$Y" "$R" "$G" "$B"

case "$MODE" in
--near)
    EXPECT="${7:?--near needs a #rrggbb}"; TOL="${8:-24}"
    HEX="${EXPECT#\#}"
    ER=$((16#${HEX:0:2})); EG=$((16#${HEX:2:2})); EB=$((16#${HEX:4:2}))
    DR=$(( R > ER ? R - ER : ER - R ))
    DG=$(( G > EG ? G - EG : EG - G ))
    DB=$(( B > EB ? B - EB : EB - B ))
    if [ "$DR" -le "$TOL" ] && [ "$DG" -le "$TOL" ] && [ "$DB" -le "$TOL" ]; then
        echo "PASS near $EXPECT (tol $TOL)"
    else
        echo "FAIL near $EXPECT (tol $TOL): off by r=$DR g=$DG b=$DB" >&2
        exit 1
    fi
    ;;
--dominant)
    CH="${7:?--dominant needs r, g or b}"; MARGIN="${8:-18}"
    case "$CH" in
    r) V=$R; A=$G; Bc=$B ;;
    g) V=$G; A=$R; Bc=$B ;;
    b) V=$B; A=$R; Bc=$G ;;
    *) echo "channel must be r, g or b" >&2; exit 2 ;;
    esac
    if [ $((V - A)) -ge "$MARGIN" ] && [ $((V - Bc)) -ge "$MARGIN" ]; then
        echo "PASS $CH dominant by >= $MARGIN"
    else
        echo "FAIL $CH not dominant by $MARGIN: got $V vs $A and $Bc" >&2
        exit 1
    fi
    ;;
*)
    echo "unknown mode: $MODE" >&2; exit 2 ;;
esac
