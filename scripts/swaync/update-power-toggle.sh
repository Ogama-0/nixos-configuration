#!/usr/bin/env sh
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

set -e

p="$(powerprofilesctl get)"
if [ "$p" = "performance" ]; then
  echo "{\"label\":\"󰓅\"}"
elif [ "$p" = "balanced" ]; then
  echo "{\"label\":\"󰾅\"}"
else
  echo "{\"label\":\"󰁹\"}"
fi
