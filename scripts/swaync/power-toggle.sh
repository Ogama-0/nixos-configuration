#!/usr/bin/env sh

export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

p="$(powerprofilesctl get)"

if [ "$p" = "performance" ]; then
  powerprofilesctl set balanced
  notify-send "Mode set to : balanced" --icon power --app-name "system"
elif [ "$p" = "balanced" ]; then
  powerprofilesctl set power-saver
  notify-send "Mode set to : eco" --icon power --app-name "system"
else
  powerprofilesctl set performance
  notify-send "Mode set to : performance" --icon power --app-name "system"
fi
