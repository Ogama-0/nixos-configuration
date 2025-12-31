#!/usr/bin/env sh
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"


if pgrep -x hyprsunset > /dev/null; then
  echo "{\"active\":false,\"label\":\"🔅\"}"
else
  echo "{\"active\":true,\"label\":\"🌙\"}"
fi

