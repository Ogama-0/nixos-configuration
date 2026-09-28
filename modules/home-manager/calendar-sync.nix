{
  config,
  lib,
  pkgs,
  ...
}:

let
  calendarsRoot = "${config.home.homeDirectory}/.local/share/calendars";
  statusDir = "${config.home.homeDirectory}/.local/state/vdirsyncer";
  calendarsSopsFile = ../../sops/calendars.yaml;

  # One entry per ICS subscription. Each gets its own local calendar dir,
  # vdirsyncer pair and khal calendar block; khal (and so the Calendar.qml
  # widget) merges events across all of them automatically. To add another
  # calendar: add its `<name>_calendar_ics_url` key to sops/calendars.yaml
  # (`sops sops/calendars.yaml`), then add an entry here.
  calendars = {
    harmo_1 = "harmo_1_calendar_ics_url";
    class_B1 = "class_B1_calendar_ics_url";
    sortie = "sortie_calendar_ics_url";
    work = "work_calendar_ics_url";
  };

  calendarDir = name: "${calendarsRoot}/${name}";
in
{
  sops.secrets = lib.mapAttrs' (
    _: secret: lib.nameValuePair secret { sopsFile = calendarsSopsFile; }
  ) calendars;

  home.packages = [
    pkgs.vdirsyncer
    pkgs.khal
  ];

  xdg.configFile."khal/config".text = ''
    [calendars]
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: _: ''
        [[${name}]]
        path = ${calendarDir name}
        type = calendar
      '') calendars
    )}

    [locale]
    local_timezone = Europe/Paris
    timeformat = %H:%M
    dateformat = %Y-%m-%d
    longdateformat = %Y-%m-%d
    datetimeformat = %Y-%m-%d %H:%M
    longdatetimeformat = %Y-%m-%d %H:%M
  '';

  # Must run after sops-nix has decrypted secrets to disk - otherwise the
  # `cat`s below read nonexistent files and vdirsyncer syncs empty URLs.
  home.activation.calendarSync = lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
        run mkdir -p "${statusDir}" "$HOME/.config/vdirsyncer"
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: _: ''
            run mkdir -p "${calendarDir name}"
          '') calendars
        )}

        run cat > "$HOME/.config/vdirsyncer/config" <<EOF
    [general]
    status_path = "${statusDir}"

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: secret: ''
        [pair ${name}_calendar]
        a = "${name}_calendar_local"
        b = "${name}_calendar_remote"
        collections = null

        [storage ${name}_calendar_local]
        type = "filesystem"
        path = "${calendarDir name}"
        fileext = ".ics"

        [storage ${name}_calendar_remote]
        type = "http"
        url = "$(cat ${config.sops.secrets.${secret}.path})"
      '') calendars
    )}
    EOF

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: _: ''
            run ${pkgs.vdirsyncer}/bin/vdirsyncer discover ${name}_calendar || true
          '') calendars
        )}
  '';
}
