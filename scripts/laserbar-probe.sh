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

magick_cmd() {
    if command -v magick >/dev/null 2>&1; then
        magick "$@"
    else
        nix shell nixpkgs#imagemagick --command magick "$@"
    fi
}

# Average one region of one png, as "R G B". Hard-fails on a missing file:
# magick prints an error and yields 0 0 0, which silently reads as "black" and
# can make an assertion pass against a render that never happened.
region_avg() {
    [ -s "$1" ] || { echo "no such render (or empty): $1" >&2; exit 2; }
    magick_cmd "$1" -crop "${4}x${5}+${2}+${3}" +repage -resize 1x1\! -depth 8 \
        -format '%[fx:int(255*r)] %[fx:int(255*g)] %[fx:int(255*b)]' info:
}

# --diff: the same region of two renders, asserting the first is darker than
# the second by a margin. Used where the feature's claim IS a difference -
# pinching strands removes white light from a stretch of beam - and where an
# absolute colour would just be fitting the test to the output.
if [ "${1:-}" = "--diff" ]; then
    A="${2:?}"; B="${3:?}"; X="${4:?}"; Y="${5:?}"; W="${6:?}"; H="${7:?}"; MARGIN="${8:-10}"
    # Assigned first, then read: a failure inside $( ) in a herestring is lost,
    # which is how an assertion once passed against a render that never
    # happened. As an assignment, set -e sees the non-zero status.
    AVG_A="$(region_avg "$A" "$X" "$Y" "$W" "$H")"
    AVG_B="$(region_avg "$B" "$X" "$Y" "$W" "$H")"
    read -r AR AG AB <<<"$AVG_A"
    read -r BR BG BB <<<"$AVG_B"
    # Rec.601 luma, integer maths: white strands raise it on any accent.
    ALUM=$(( (299 * AR + 587 * AG + 114 * AB) / 1000 ))
    BLUM=$(( (299 * BR + 587 * BG + 114 * BB) / 1000 ))
    printf 'luma %s=%s %s=%s delta=%s\n' "$(basename "$A")" "$ALUM" "$(basename "$B")" "$BLUM" "$((BLUM - ALUM))"
    if [ $((BLUM - ALUM)) -ge "$MARGIN" ]; then
        echo "PASS first is darker by >= $MARGIN"
        exit 0
    fi
    echo "FAIL first not darker by $MARGIN: $ALUM vs $BLUM" >&2
    exit 1
fi

PNG="${1:?usage: laserbar-probe.sh <png> <x> <y> <w> <h> --near|--dominant ... | --diff a b x y w h [margin]}"
X="${2:?}"; Y="${3:?}"; W="${4:?}"; H="${5:?}"; MODE="${6:?}"
[ -f "$PNG" ] || { echo "no such png: $PNG" >&2; exit 2; }

AVG="$(region_avg "$PNG" "$X" "$Y" "$W" "$H")"
read -r R G B <<<"$AVG"

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
--darker-than)
    # "There is ink in this band" - a region containing dark glyphs on a light
    # plate averages well below the plate itself. Stated as a margin against a
    # known colour rather than an absolute, so it does not encode whatever the
    # renderer happened to produce.
    EXPECT="${7:?--darker-than needs a #rrggbb}"; MARGIN="${8:-25}"
    HEX="${EXPECT#\#}"
    ER=$((16#${HEX:0:2})); EG=$((16#${HEX:2:2})); EB=$((16#${HEX:4:2}))
    LUM=$(( (299 * R + 587 * G + 114 * B) / 1000 ))
    ELUM=$(( (299 * ER + 587 * EG + 114 * EB) / 1000 ))
    if [ $((ELUM - LUM)) -ge "$MARGIN" ]; then
        echo "PASS luma $LUM is >= $MARGIN below $EXPECT ($ELUM)"
    else
        echo "FAIL luma $LUM not $MARGIN below $EXPECT ($ELUM)" >&2
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
