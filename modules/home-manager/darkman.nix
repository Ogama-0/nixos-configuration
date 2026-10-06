{ pkgs, lib, config, ... }:
let
  dconfExe = "${pkgs.dconf}/bin/dconf";

  bashExe = "${pkgs.bash}/bin/bash";
  coreutils = pkgs.coreutils;

  # Shared with the greeter (pkgs/greetd-proxy), which has to make the same
  # sunrise/sunset decision before any user session exists.
  tzTable = import ../lib/timezone-coords.nix;
  timezoneCoords = tzTable.coords;
  fallbackLat = tzTable.fallback.lat;
  fallbackLng = tzTable.fallback.lng;

  timezoneCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (tz: c: ''
      if [ "$TZ_VALUE" = "${tz}" ]; then LAT="${c.lat}"; LNG="${c.lng}"; fi
    '') timezoneCoords
  );

  syncScript = pkgs.writeShellScript "darkman-timezone-sync" ''
    set -eu
    TZ_VALUE=""
    if [ -L /etc/localtime ]; then
      REALPATH=$(${coreutils}/bin/readlink -f /etc/localtime)
      TZ_VALUE="''${REALPATH##*/zoneinfo/}"
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
    ${pkgs.systemd}/bin/systemctl --user restart darkman.service || true
  '';
in
{
  home.activation.darkmanTimezoneSync = lib.hm.dag.entryAfter [ "linkGeneration" "tofiConfigDefault" "quickshellLockDefault" ] ''
    ${bashExe} ${syncScript}
  '';

  services.darkman = {
    enable = true;
    package = pkgs.darkman;

    # Kept empty on purpose: home-manager's own darkman module manages
    # xdg.configFile."darkman/config.yaml" via
    # `mkIf (cfg.settings != {}) { source = ...; }`, which would symlink
    # that path to a read-only Nix store file. darkmanTimezoneSync (below)
    # needs to write that same path directly on every activation, so
    # settings must stay `{}` to keep home-manager from ever managing it.
    settings = { };

    darkModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
      '';
      mako = ''
        ${pkgs.mako}/bin/makoctl mode -r light
      '';
      tofi = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/tofi/config-dark" "${config.xdg.configHome}/tofi/config"
      '';
      quickshell-lock-theme = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/quickshell/widgets/components/Lock-dark.qml" "${config.xdg.configHome}/quickshell/widgets/components/Lock.qml"
      '';
    };

    lightModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
      '';
      mako = ''
        ${pkgs.mako}/bin/makoctl mode -a light
      '';
      tofi = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/tofi/config-light" "${config.xdg.configHome}/tofi/config"
      '';
      quickshell-lock-theme = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/quickshell/widgets/components/Lock-light.qml" "${config.xdg.configHome}/quickshell/widgets/components/Lock.qml"
      '';
    };
  };
}
