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
# stdout, so a fixture can just say what it found. This greps for the sentinel
# the fixture prints when every case passed.
#
# Quickshell does not exit on its own - it is a shell, it waits. So this tails
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

[ -f "$fixture" ] || { echo "no such fixture: $fixture" >&2; exit 2; }

log=$(mktemp)
trap 'rm -f "$log"' EXIT

# Wayland is almost certainly running; without this quickshell picks it up and
# the fixture waits for a compositor surface that nothing will ever show.
QT_QPA_PLATFORM=offscreen timeout "$timeout_s" quickshell -p "$fixture" >"$log" 2>&1 &
qs=$!

found=0
# Poll rather than `tail -f | grep -q`: grep closing the pipe leaves quickshell
# writing to a dead fd and the kill below racing a process that has not noticed.
for _ in $(seq 1 $((timeout_s * 10))); do
    if grep -qF -- "$expected" "$log" 2>/dev/null; then found=1; break; fi
    kill -0 "$qs" 2>/dev/null || break
    sleep 0.1
done

kill "$qs" 2>/dev/null
wait "$qs" 2>/dev/null
rc=$?

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
