#!/usr/bin/env bash
# Assert something a QML component computed, without rendering it.
#
#   qml-logic-test.sh <fixture.qml> <expected-substring>
#
# The render fixtures in tests/laserbar/ answer "does this look right". They
# cannot answer "does normalize() fold +33 6 76 72 48 57 onto 076-724-8570",
# because the only way to see that on screen is to draw the answer as text and
# probe pixels of a glyph, which asserts on the font as much as on the code.
#
# Quickshell runs under QT_QPA_PLATFORM=offscreen and console.log reaches
# stdout, so a fixture can simply say what it found. This greps for the
# sentinel the fixture prints when every case passed.
#
# The tree is generated from the WORKING TREE with `nix eval`, exactly as
# laserbar-preview.sh does, and for the same reason - but also for a second
# one that does not apply there: the QML in modules/ is not valid QML. It is
# full of @token@ placeholders that only become colours after the substitution
# in modules/lib/qml-theme.nix. Running a fixture straight off the source tree
# fails on the first themed component it touches.
#
# Set QML_LOGIC_TREE to a tree a previous run generated to skip the eval; the
# whole point of that is a tight loop while writing one fixture, so it is on
# you to regenerate after editing a component.
#
# Quickshell does not exit on its own - it is a shell, it waits. So this polls
# its output and kills it the moment the sentinel appears, instead of sitting
# out the timeout on every green run. A fixture that never prints costs the
# full timeout, which is the right way round: failure is the slow path.
#
# A fixture that never loaded prints no sentinel, which looks exactly like a
# fixture whose assertions failed - so on failure the whole captured output is
# printed rather than swallowed. Nearly every "my test fails and I cannot see
# why" here is a QML import error scrolling past in that output.
set -uo pipefail

if [ $# -lt 2 ]; then
    echo "usage: $0 <fixture.qml> <expected-substring>" >&2
    exit 2
fi

fixture="$1"
expected="$2"
timeout_s="${QML_LOGIC_TIMEOUT:-25}"
variant="${QML_LOGIC_VARIANT:-dark}"

[ -f "$fixture" ] || { echo "no such fixture: $fixture" >&2; exit 2; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RT="$(mktemp -d)"
cleanup() {
    [ -n "${QS_PID:-}" ] && kill "$QS_PID" 2>/dev/null
    rm -rf "$RT"
}
trap cleanup EXIT

if [ -n "${QML_LOGIC_TREE:-}" ]; then
    TREE="$QML_LOGIC_TREE"
    [ -d "$TREE" ] || { echo "QML_LOGIC_TREE is not a directory: $TREE" >&2; exit 2; }
else
    TREE="$RT/tree"
    mkdir -p "$TREE"
    nix eval --json \
        "$REPO#homeConfigurations.personal.config.xdg.configFile" \
        --apply 'cf:
          let names = builtins.filter
                (n: builtins.match "quickshell/widgets-'"$variant"'/.*" n != null)
                (builtins.attrNames cf);
          in builtins.listToAttrs
               (map (n: { name = n; value = cf.${n}.text; }) names)' \
        > "$RT/tree.json" || { echo "nix eval failed - is every new file git-added?" >&2; exit 2; }

    python3 - "$RT/tree.json" "$TREE" "$variant" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1]))
root = sys.argv[2]
prefix = "quickshell/widgets-%s/" % sys.argv[3]
for name, text in data.items():
    path = os.path.join(root, name[len(prefix):])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)
PY
fi

# The fixture replaces shell.qml; components/ comes from the evaluated tree,
# so a fixture imports them exactly as the real shell does.
work="$RT/run"
cp -r "$TREE" "$work"
cp "$fixture" "$work/shell.qml"

log="$RT/out.log"

# Wayland is almost certainly running; without this quickshell picks it up and
# the fixture waits for a compositor surface that nothing will ever show.
QT_QPA_PLATFORM=offscreen timeout "$timeout_s" quickshell -p "$work/shell.qml" >"$log" 2>&1 &
QS_PID=$!

found=0
# Poll rather than `tail -f | grep -q`: grep closing the pipe leaves quickshell
# writing to a dead fd and the kill below racing a process that has not noticed.
for _ in $(seq 1 $((timeout_s * 10))); do
    if grep -qF -- "$expected" "$log" 2>/dev/null; then found=1; break; fi
    kill -0 "$QS_PID" 2>/dev/null || break
    sleep 0.1
done

kill "$QS_PID" 2>/dev/null
wait "$QS_PID" 2>/dev/null
rc=$?
QS_PID=

# One last look: the sentinel may have landed in the gap between the final poll
# and the process exiting.
grep -qF -- "$expected" "$log" 2>/dev/null && found=1

if [ "$found" -eq 1 ]; then
    echo "ok: $(basename "$fixture") printed '$expected'"
    exit 0
fi

echo "FAIL: $(basename "$fixture") never printed '$expected' (quickshell exit $rc)" >&2
echo "--- captured output ---" >&2
cat "$log" >&2
echo "--- end ---" >&2
exit 1
