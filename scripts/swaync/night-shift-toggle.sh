#!/usr/bin/env sh
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"


if pgrep -x hyprsunset > /dev/null; then
  pkill hyprsunset
  notify-send "Mode nuit désactivé" --icon "weather-clear" --app-name="swaync"
else
  hyprsunset &
  notify-send "Mode nuit activé"  --icon "weather-clear-night" --app-name="swaync"
fi

