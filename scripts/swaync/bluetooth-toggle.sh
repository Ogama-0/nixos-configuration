#!/usr/bin/env sh
set -e
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

if bluetoothctl show | grep -q "Powered: yes"; then
  bluetoothctl power off
  notify-send "Bluetooth off" --app-name="swaync" --icon=bluetooth
else
  bluetoothctl power on
  notify-send "Bluetooth on" --app-name="swaync" --icon=bluetooth
fi
