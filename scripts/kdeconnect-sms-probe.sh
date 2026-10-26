#!/usr/bin/env bash
# Capture one real SMS payload from KDE Connect, and prove the phone answers.
#
#   kdeconnect-sms-probe.sh [seconds=15]
#
# The desktop asks for conversations on org.kde.kdeconnect.device.sms, but the
# answers come back on a DIFFERENT interface, org.kde.kdeconnect.device.conversations,
# as signals. That interface does not show up under `busctl introspect` on the
# sms object - it is registered by the plugin when the phone first replies - so
# the only honest way to see its shape is to watch the bus while asking.
#
# Nothing here changes anything. requestAllConversations asks the phone to send
# what it already has.
#
# Silence is the interesting failure. It means the request went out and the
# phone did not answer, which on a paired device with the plugin loaded almost
# always means the Android app has not been granted SMS permission.
set -uo pipefail

window="${1:-15}"

command -v kdeconnect-cli >/dev/null || { echo "kdeconnect-cli not on PATH" >&2; exit 2; }

line=$(kdeconnect-cli -a --id-name-only 2>/dev/null | sed '/^[[:space:]]*$/d' | head -1)
[ -n "$line" ] || { echo "No reachable KDE Connect device. Pair one and bring it onto the network." >&2; exit 2; }

id=${line%% *}
name=${line#* }
echo "device: $name ($id)"

obj="/modules/kdeconnect/devices/$id/sms"
log=$(mktemp)
trap 'rm -f "$log"' EXIT

busctl --user monitor org.kde.kdeconnect >"$log" 2>&1 &
mon=$!
sleep 1

echo "asking for all conversations, listening ${window}s..."
busctl --user call org.kde.kdeconnect "$obj" org.kde.kdeconnect.device.sms requestAllConversations \
    || { kill "$mon" 2>/dev/null; echo "the request itself failed" >&2; exit 2; }

sleep "$window"
kill "$mon" 2>/dev/null
wait "$mon" 2>/dev/null

# One record per bus message. busctl monitor separates them with a blank line,
# so paragraph mode gets whole messages rather than the one matching line.
hits=$(awk -v RS='' '/device\.conversations/' "$log")

if [ -z "$hits" ]; then
    echo >&2
    echo "NOTHING CAME BACK." >&2
    echo "The request went out and the phone said nothing for ${window}s." >&2
    echo >&2
    echo "On the phone, open KDE Connect and check:" >&2
    echo "  - the SMS plugin is enabled for this desktop" >&2
    echo "  - Android has granted KDE Connect the SMS permission" >&2
    echo "    (Settings > Apps > KDE Connect > Permissions > SMS)" >&2
    exit 1
fi

echo
echo "=== org.kde.kdeconnect.device.conversations traffic ==="
printf '%s\n' "$hits"
