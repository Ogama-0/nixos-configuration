#!/usr/bin/env bash
# Render a laser-bar fixture headlessly and screenshot it.
#
#   laserbar-preview.sh <entry.qml> <out.png> [battery-fraction]
#
# The themed QML tree is evaluated out of the WORKING TREE with `nix eval`,
# not copied from ~/.config/quickshell. The installed copy is whatever the
# last home-manager switch produced, so probing it would verify stale code.
#
# The bar is momentary - it only draws while revealed - so this reveals it
# over the same `laserbar` IPC the Insert binding uses, then grims the output.
set -euo pipefail

ENTRY="${1:?usage: laserbar-preview.sh <entry.qml> <out.png> [battery-fraction]}"
OUT="${2:?missing output png}"
BATTERY="${3:-0.5}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ENTRY" ] || { echo "no such fixture: $ENTRY" >&2; exit 2; }

RT="$(mktemp -d)"
TREE="$RT/tree"
cleanup() {
    [ -n "${QS_PID:-}" ] && kill "$QS_PID" 2>/dev/null || true
    [ -n "${SWAY_PID:-}" ] && kill "$SWAY_PID" 2>/dev/null || true
    sleep 0.2
    rm -rf "$RT"
}
trap cleanup EXIT

# --- generate the themed tree from the working tree -------------------------
# One eval for every file, not one per file: nix's startup cost dominates.
mkdir -p "$TREE"
nix eval --json \
    "$REPO#homeConfigurations.personal.config.xdg.configFile" \
    --apply 'cf:
      let names = builtins.filter
            (n: builtins.match "quickshell/widgets-dark/.*" n != null)
            (builtins.attrNames cf);
      in builtins.listToAttrs
           (map (n: { name = n; value = cf.${n}.text; }) names)' \
    > "$RT/tree.json"

python3 - "$RT/tree.json" "$TREE" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1]))
root = sys.argv[2]
prefix = "quickshell/widgets-dark/"
for name, text in data.items():
    rel = name[len(prefix):]
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)
print(f"{len(data)} files", file=sys.stderr)
PY

# The fixture replaces shell.qml; components/ comes from the evaluated tree.
cp "$ENTRY" "$TREE/shell.qml"

# --- nested headless compositor ---------------------------------------------
export XDG_RUNTIME_DIR="$RT"
export WLR_BACKENDS=headless
export WLR_LIBINPUT_NO_DEVICES=1
export SWAYSOCK="$RT/sway.sock"
# Percentage, same unit as /sys/class/power_supply/BAT*/capacity, which is what
# it stands in for.
LASERBAR_FAKE_BATTERY="$(awk -v f="$BATTERY" 'BEGIN { printf "%d", f * 100 }')"
export LASERBAR_FAKE_BATTERY

cat > "$RT/sway.conf" <<CONF
output HEADLESS-1 resolution 1920x1080
exec sleep infinity
CONF

sway -c "$RT/sway.conf" >"$RT/sway.log" 2>&1 &
SWAY_PID=$!
for _ in $(seq 60); do [ -S "$SWAYSOCK" ] && break; sleep 0.25; done
[ -S "$SWAYSOCK" ] || { echo "sway did not start" >&2; tail -5 "$RT/sway.log" >&2; exit 1; }

WAYLAND_DISPLAY="$(ls "$RT" | grep -m1 '^wayland-[0-9]*$')"
export WAYLAND_DISPLAY

quickshell -p "$TREE/shell.qml" >"$RT/qs.log" 2>&1 &
QS_PID=$!
# Wait for the shell to report itself loaded rather than guessing a sleep.
for _ in $(seq 60); do grep -q "Configuration Loaded" "$RT/qs.log" && break; sleep 0.25; done
grep -q "Configuration Loaded" "$RT/qs.log" || {
    echo "quickshell did not load the fixture" >&2; tail -20 "$RT/qs.log" >&2; exit 1; }
sleep 1

quickshell -p "$TREE/shell.qml" ipc call laserbar reveal >>"$RT/qs.log" 2>&1 || true
# The beams animate over 90ms; give them room to finish travelling.
sleep 1

grim -o HEADLESS-1 "$OUT"
cp "$RT/qs.log" "${OUT%.png}.log" 2>/dev/null || true
[ -s "$OUT" ] || { echo "grim produced nothing" >&2; tail -20 "$RT/qs.log" >&2; exit 1; }

# A QML error leaves the surface blank rather than failing the run, so surface
# them even on success.
if grep -qi "error\|warning:" "$RT/qs.log"; then
    echo "--- quickshell log ---" >&2
    grep -i "error\|warning:" "$RT/qs.log" >&2 || true
fi
echo "wrote $OUT (battery ${LASERBAR_FAKE_BATTERY}%)"
