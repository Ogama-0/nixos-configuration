#!/usr/bin/env bash
# Sample quickshell's CPU while the bar is held open.
#
#   laserbar-cpu.sh <entry.qml> [seconds=8] [battery-fraction]
#
# The bar only animates while revealed, so an idle measurement says nothing.
# This reveals it and then samples utime+stime out of /proc, which is the cost
# the user pays for the whole time they hold the key down.
set -euo pipefail

ENTRY="${1:?usage: laserbar-cpu.sh <entry.qml> [seconds] [battery-fraction]}"
SECONDS_TO_SAMPLE="${2:-8}"
BATTERY="${3:-0.5}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RT="$(mktemp -d)"
TREE="$RT/tree"
cleanup() {
    [ -n "${QS_PID:-}" ] && kill "$QS_PID" 2>/dev/null || true
    [ -n "${SWAY_PID:-}" ] && kill "$SWAY_PID" 2>/dev/null || true
    sleep 0.2
    rm -rf "$RT"
}
trap cleanup EXIT

mkdir -p "$TREE"
nix eval --json "$REPO#homeConfigurations.personal.config.xdg.configFile" \
    --apply 'cf:
      let names = builtins.filter
            (n: builtins.match "quickshell/widgets-dark/.*" n != null)
            (builtins.attrNames cf);
      in builtins.listToAttrs
           (map (n: { name = n; value = cf.${n}.text; }) names)' \
    > "$RT/tree.json" 2>/dev/null

python3 - "$RT/tree.json" "$TREE" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1]))
prefix = "quickshell/widgets-dark/"
for name, text in data.items():
    path = os.path.join(sys.argv[2], name[len(prefix):])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)
PY
cp "$ENTRY" "$TREE/shell.qml"

export XDG_RUNTIME_DIR="$RT" WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1
export SWAYSOCK="$RT/sway.sock"
LASERBAR_FAKE_BATTERY="$(awk -v f="$BATTERY" 'BEGIN { printf "%d", f * 100 }')"
export LASERBAR_FAKE_BATTERY

printf 'output HEADLESS-1 resolution 1920x1080\nexec sleep infinity\n' > "$RT/sway.conf"
sway -c "$RT/sway.conf" >"$RT/sway.log" 2>&1 &
SWAY_PID=$!
for _ in $(seq 60); do [ -S "$SWAYSOCK" ] && break; sleep 0.25; done
WAYLAND_DISPLAY="$(ls "$RT" | grep -m1 '^wayland-[0-9]*$')"
export WAYLAND_DISPLAY

quickshell -p "$TREE/shell.qml" >"$RT/qs.log" 2>&1 &
QS_PID=$!
for _ in $(seq 60); do grep -q "Configuration Loaded" "$RT/qs.log" && break; sleep 0.25; done
sleep 1
quickshell -p "$TREE/shell.qml" ipc call laserbar reveal >>"$RT/qs.log" 2>&1 || true
sleep 1

ticks() { awk '{ print $14 + $15 }' "/proc/$QS_PID/stat"; }
HZ="$(getconf CLK_TCK)"
T0="$(ticks)"
sleep "$SECONDS_TO_SAMPLE"
T1="$(ticks)"

awk -v t0="$T0" -v t1="$T1" -v hz="$HZ" -v s="$SECONDS_TO_SAMPLE" \
    'BEGIN { printf "cpu: %.1f%% over %ss while revealed\n", 100 * (t1 - t0) / hz / s, s }'
