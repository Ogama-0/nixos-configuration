#!/usr/bin/env sh
set -e

export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

if bluetoothctl show | grep -q "Powered: yes"; then
  echo "{\"active\":true,\"label\":\"󰂯\"}"
else
  echo "{\"active\":false,\"label\":\"󰂲\"}"
fi
