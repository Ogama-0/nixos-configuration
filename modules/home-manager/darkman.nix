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
    ${pkgs.systemd}/bin/systemctl --user restart darkman.service || true
  '';
in
{
  home.activation.darkmanTimezoneSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
      waybar-theme = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/waybar/colors-dark.css" "${config.xdg.configHome}/waybar/colors.css"
        ${pkgs.procps}/bin/pkill -x -SIGUSR2 waybar || true
      '';
      tofi = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/tofi/config-dark" "${config.xdg.configHome}/tofi/config"
      '';
    };

    lightModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
      '';
      mako = ''
        ${pkgs.mako}/bin/makoctl mode -a light
      '';
      waybar-theme = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/waybar/colors-light.css" "${config.xdg.configHome}/waybar/colors.css"
        ${pkgs.procps}/bin/pkill -x -SIGUSR2 waybar || true
      '';
      tofi = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/tofi/config-light" "${config.xdg.configHome}/tofi/config"
      '';
    };
  };
}
