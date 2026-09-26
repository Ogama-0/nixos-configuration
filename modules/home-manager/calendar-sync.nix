{ config, lib, pkgs, ... }:

let
  calendarDir = "${config.home.homeDirectory}/.local/share/calendars/proton";
  statusDir = "${config.home.homeDirectory}/.local/state/vdirsyncer";
in
{
  sops.secrets.proton_calendar_ics_url.sopsFile = ../../sops/proton-calendar.yaml;

  home.packages = [
    pkgs.vdirsyncer
    pkgs.khal
  ];

  xdg.configFile."khal/config".text = ''
    [calendars]
    [[proton]]
    path = ${calendarDir}
    type = calendar

    [locale]
    local_timezone = Europe/Paris
    timeformat = %H:%M
    dateformat = %Y-%m-%d
    longdateformat = %Y-%m-%d
    datetimeformat = %Y-%m-%d %H:%M
    longdatetimeformat = %Y-%m-%d %H:%M
  '';

  home.activation.protonCalendarSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${calendarDir}" "${statusDir}" "$HOME/.config/vdirsyncer"

    run cat > "$HOME/.config/vdirsyncer/config" <<EOF
[general]
status_path = "${statusDir}"

[pair proton_calendar]
a = "proton_calendar_local"
b = "proton_calendar_remote"
collections = null

[storage proton_calendar_local]
type = "filesystem"
path = "${calendarDir}"
fileext = ".ics"

[storage proton_calendar_remote]
type = "http"
url = "$(cat ${config.sops.secrets.proton_calendar_ics_url.path})"
EOF

    run ${pkgs.vdirsyncer}/bin/vdirsyncer discover proton_calendar || true
  '';
}
