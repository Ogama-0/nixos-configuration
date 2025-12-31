#!/usr/bin/env sh
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

if [ "$(nmcli radio wifi)" = "enabled" ]; then
  nmcli radio wifi off
  notify-send "Wi-Fi off" --icon network-wireless-offline --app-name "system"
else
  nmcli radio wifi on
  notify-send "Wi-Fi on" --icon network-wireless-offline --app-name "system"
fi
