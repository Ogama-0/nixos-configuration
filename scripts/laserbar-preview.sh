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
# over the same `laserbar` IPC the bar itself uses, then grims the output.
set -euo pipefail

ENTRY="${1:?usage: laserbar-preview.sh <entry.qml> <out.png> [battery-fraction] [WxH]}"
OUT="${2:?missing output png}"
BATTERY="${3:-0.5}"
# Output size, so the bar can be checked at a resolution it would have to
# scale itself up for.
RESOLUTION="${4:-1920x1080}"
# Which themed tree to render. Both variants are generated from the same QML
# with different @token@ substitutions, so a render only ever exercises one of
# them - and the light one has its own legibility problems (base0B is pale on
# cream) that a dark render cannot show.
VARIANT="${LASERBAR_VARIANT:-dark}"
# A command run inside the nested session after the bar is revealed and the
# fixture has settled, before the screenshot. This is how dismissal is tested
# at all: Escape, a click and a workspace switch cannot be asserted from a
# static render, and all three are things a user does TO the shell.
#
#   LASERBAR_EXEC='swaymsg workspace 2'
#   LASERBAR_EXEC='wtype -k Escape'
#   LASERBAR_EXEC='swaymsg seat - cursor set 100 100; swaymsg seat - cursor press button1'
#
# SWAYSOCK and WAYLAND_DISPLAY are already exported when it runs.
EXEC_AFTER="${LASERBAR_EXEC:-}"

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

# --- generate the themed tree from the working tree -------------------------
# One eval for every file, not one per file: nix's startup cost dominates.
mkdir -p "$TREE"
nix eval --json \
    "$REPO#homeConfigurations.personal.config.xdg.configFile" \
    --apply 'cf:
      let names = builtins.filter
            (n: builtins.match "quickshell/widgets-'"$VARIANT"'/.*" n != null)
            (builtins.attrNames cf);
      in builtins.listToAttrs
           (map (n: { name = n; value = cf.${n}.text; }) names)' \
    > "$RT/tree.json"

python3 - "$RT/tree.json" "$TREE" "$VARIANT" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1]))
root = sys.argv[2]
prefix = "quickshell/widgets-%s/" % sys.argv[3]
for name, text in data.items():
    rel = name[len(prefix):]
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)
print(f"{len(data)} files", file=sys.stderr)
PY

# The fixture replaces shell.qml; components/ comes from the evaluated tree.
#
# ENTRY=real keeps the GENERATED shell.qml instead, which is the only way to
# find out whether the thing that actually runs loads. A fixture instantiates
# one or two components; the real shell instantiates all of them together,
# and a QML load error there - two handlers for one signal, say - is
# invisible to every fixture in this directory.
if [ "$ENTRY" = "real" ]; then
    [ -f "$TREE/shell.qml" ] || { echo "no generated shell.qml in the tree" >&2; exit 2; }
else
    [ -f "$ENTRY" ] || { echo "no such fixture: $ENTRY" >&2; exit 2; }
    cp "$ENTRY" "$TREE/shell.qml"
fi

# --- nested headless compositor ---------------------------------------------
export XDG_RUNTIME_DIR="$RT"
# Inherited from the real session otherwise, which would point the bar's
# Quickshell.I3 at the host compositor's workspaces instead of this nested
# one's - making any render that uses live workspace data depend on whatever
# the user happens to have open.
unset I3SOCK
export WLR_BACKENDS=headless
export WLR_LIBINPUT_NO_DEVICES=1
export SWAYSOCK="$RT/sway.sock"
# Percentage, same unit as /sys/class/power_supply/BAT*/capacity, which is what
# it stands in for.
LASERBAR_FAKE_BATTERY="$(awk -v f="$BATTERY" 'BEGIN { printf "%d", f * 100 }')"
export LASERBAR_FAKE_BATTERY

cat > "$RT/sway.conf" <<CONF
output HEADLESS-1 resolution $RESOLUTION
exec sleep infinity

# Mirrors modes.panel from the real sway config. The panel holds no
# keyboard focus, so Escape can only reach it by sway intercepting that one
# key in a mode - without this block the dismissal test fails for a reason
# that has nothing to do with the panel.
mode "panel" {
    # -p, not -c widgets: the nested shell is launched by path and has no
    # instance name, so the real config's IPC target finds nothing here.
    bindsym Escape mode default; exec quickshell -p $TREE/shell.qml ipc call panel dismiss
}
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

# LASERBAR_RETRACT=1 captures the released state instead: the bar must go back
# to nothing, with no module left painted.
if [ "${LASERBAR_RETRACT:-}" = "1" ]; then
    quickshell -p "$TREE/shell.qml" ipc call laserbar hide >>"$RT/qs.log" 2>&1 || true
    sleep 1
fi

if [ -n "$EXEC_AFTER" ]; then
    sh -c "$EXEC_AFTER" >>"$RT/qs.log" 2>&1 || echo "LASERBAR_EXEC failed" >>"$RT/qs.log"
    # Dismissal animations are ~200-300ms; give them room to finish.
    sleep 1
fi

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
