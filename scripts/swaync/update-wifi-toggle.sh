#!/usr/bin/env sh
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

if [ "$(nmcli radio wifi)" = "enabled" ]; then
  echo "{\"active\":true,\"label\":\"󰤨\"}"
else
  echo "{\"active\":false,\"label\":\"󰤨\"}"
fi
