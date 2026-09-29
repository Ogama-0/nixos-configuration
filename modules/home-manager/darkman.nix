{ pkgs, lib, config, ... }:
let
  dconfExe = "${pkgs.dconf}/bin/dconf";

  bashExe = "${pkgs.bash}/bin/bash";
  coreutils = pkgs.coreutils;

  # Mirrors host/personal/configuration.nix's time.timeZone and its two
  # commented-out travel alternates.
  timezoneCoords = {
    "Europe/Paris" = { lat = "48.8566"; lng = "2.3522"; };
    "America/Monterrey" = { lat = "25.6866"; lng = "-100.3161"; };
    "America/Mazatlan" = { lat = "23.2494"; lng = "-106.4111"; };
  };

  # Paris is the fallback for an unrecognized/missing timezone.
  fallbackLat = "48.8566";
  fallbackLng = "2.3522";

  timezoneCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (tz: c: ''
      if [ "$TZ_VALUE" = "${tz}" ]; then LAT="${c.lat}"; LNG="${c.lng}"; fi
    '') timezoneCoords
  );

  syncScript = pkgs.writeShellScript "darkman-timezone-sync" ''
    set -eu
    TZ_VALUE=""
    if [ -r /etc/timezone ]; then
      TZ_VALUE=$(${coreutils}/bin/cat /etc/timezone)
    fi
    LAT="${fallbackLat}"
    LNG="${fallbackLng}"
    ${timezoneCases}
    ${coreutils}/bin/mkdir -p "${config.xdg.configHome}/darkman"
    ${coreutils}/bin/cat > "${config.xdg.configHome}/darkman/config.yaml" <<EOF
    lat: $LAT
    lng: $LNG
    usegeoclue: false
    EOF
  '';
in
{
  home.activation.darkmanTimezoneSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${bashExe} ${syncScript}
  '';

  services.darkman = {
    enable = true;
    package = pkgs.darkman;

    settings = {
      # Defaults to Paris; Task 2 overrides this from /etc/timezone at
      # every home-manager activation.
      lat = 48.8566;
      lng = 2.3522;
      usegeoclue = false;
    };

    darkModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
      '';
    };

    lightModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
      '';
    };
  };
}
