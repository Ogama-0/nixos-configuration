#!/usr/bin/env bash
# Load and exercise the greeter without logging out. See tests/greeter/README.md.
#
#   scripts/greeter-check.sh
#
# The greeter's QML only becomes valid after the @token@ substitution in
# modules/features/desktop/greeter.nix, and that happens when the system
# closure is built - so this builds it and reads the rendered files out of
# the result, exactly as laserbar-preview.sh evaluates the home tree.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${1:-personal}"
fails=0

QS="${QS_BIN:-$(nix build --no-link --print-out-paths "$REPO#quickshell-multimedia")/bin/quickshell}"
SYS="$(nix build --no-link --print-out-paths \
    "$REPO#nixosConfigurations.${HOST}.config.system.build.toplevel")" || {
    echo "could not build $HOST" >&2; exit 2; }
GREETER="$SYS/etc/greeter"

# Noise the greeter user always produces: its home is /var/empty, so there is
# nowhere to put a font or shader cache, and there is no portal to register
# with. None of it is a fault and all of it would drown a real warning.
noise='fontconfig|shader cache|host portal|No writable cache|/var/(empty|cache)|Fontconfig'

nested() {
    # $1 = what to run, given $WAYLAND_DISPLAY. Everything else is a headless
    # sway so the surfaces have a real compositor and a real output.
    local RT; RT="$(mktemp -d)"
    local swaypid=""
    (
        export XDG_RUNTIME_DIR="$RT" SWAYSOCK="$RT/sway.sock"
        export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1
        unset I3SOCK WAYLAND_DISPLAY
        printf 'output HEADLESS-1 resolution 1920x1080\nexec sleep infinity\n' > "$RT/sway.conf"
        sway -c "$RT/sway.conf" >"$RT/sway.log" 2>&1 &
        swaypid=$!
        for _ in $(seq 1 60); do [ -S "$SWAYSOCK" ] && break; sleep 0.1; done
        export WAYLAND_DISPLAY=wayland-1
        eval "$1"
        kill "$swaypid" 2>/dev/null
    )
    rm -rf "$RT"
}

echo "== surfaces load =="
for s in GreeterDark GreeterLight; do
    out="$(nested "timeout 15 '$QS' -p '$GREETER/$s.qml' 2>&1" | grep -viE "$noise" | grep -E "WARN|ERROR|TypeError")"
    if [ -n "$out" ]; then
        echo "FAIL $s"; echo "$out" | sed 's/^/    /'; fails=$((fails + 1))
    else
        echo "ok   $s"
    fi
done

echo "== greetd conversation =="
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# GreetdSession sits beside the greeter surfaces now, not in a components/
# subdirectory, so the fixture needs no import path of its own.
cp "$GREETER/GreetdSession.qml" "$WORK/"
cp "$REPO/tests/greeter/greetd-session.qml" "$WORK/shell.qml"

for case in "fail:face rejected, falls through to the password:passwordRequested=true authenticated=true" \
            "ok:face accepted, never asks for a password:passwordRequested=false authenticated=true"; do
    mode="${case%%:*}"; rest="${case#*:}"; label="${rest%%:*}"; want="${rest##*:}"
    sock="$WORK/greetd-$mode.sock"
    python3 "$REPO/tests/greeter/fake-greetd.py" "$sock" "$mode" >"$WORK/fake-$mode.log" 2>&1 &
    fpid=$!
    for _ in $(seq 1 50); do grep -q READY "$WORK/fake-$mode.log" 2>/dev/null && break; sleep 0.1; done
    got="$(GREETD_SOCK="$sock" QT_QPA_PLATFORM=offscreen timeout 25 "$QS" -p "$WORK/shell.qml" 2>&1 \
            | grep -o 'RESULT .*')"
    kill "$fpid" 2>/dev/null
    if [ "$got" = "RESULT $want" ]; then
        echo "ok   $label"
    else
        echo "FAIL $label"
        echo "    wanted: RESULT $want"
        echo "    got:    ${got:-<nothing - the conversation hung>}"
        fails=$((fails + 1))
    fi
done

echo
[ "$fails" -eq 0 ] && { echo "greeter: all checks passed"; exit 0; }
echo "greeter: $fails check(s) failed" >&2
exit 1
