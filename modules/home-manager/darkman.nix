{ pkgs, lib, config, ... }:
let
  dconfExe = "${pkgs.dconf}/bin/dconf";

  alacrittyColorsPath = "${config.xdg.configHome}/alacritty/colors.toml";
  alacrittyColors = import ../lib/alacritty-colors.nix { inherit pkgs; };
  treeLink = import ../lib/quickshell-tree-link.nix { inherit pkgs; };

  helixAutoTheme = "${config.xdg.configHome}/helix/themes/auto.toml";
  helixTheme = import ../lib/helix-auto-theme.nix { inherit pkgs; };

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
  home.activation.darkmanTimezoneSync = lib.hm.dag.entryAfter [ "linkGeneration" "quickshellThemeTree" ] ''
    ${bashExe} ${syncScript}
  '';

  # The GTK themes the scripts below select between. Installed here rather
  # than in display/gtk.nix because that module is shared with `epita`, which
  # has no darkman and would gain them for nothing.
  home.packages = with pkgs; [ adw-gtk3 papirus-icon-theme ];

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
      helix = ''
        ${coreutils}/bin/install -m 644 ${helixTheme "dark"} "${helixAutoTheme}"
      '';
      alacritty = ''
        ${coreutils}/bin/install -m 644 ${alacrittyColors.dark} "${alacrittyColorsPath}"
      '';
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
        ${dconfExe} write /org/gnome/desktop/interface/gtk-theme "'adw-gtk3-dark'"
        ${dconfExe} write /org/gnome/desktop/interface/icon-theme "'Papirus-Dark'"
      '';
      mako = ''
        ${pkgs.mako}/bin/makoctl mode -r light
      '';
      quickshell-theme = ''
        ${treeLink} "${config.xdg.configHome}/quickshell/widgets-dark" "${config.xdg.configHome}/quickshell/widgets"
        ${pkgs.systemd}/bin/systemctl --user restart quickshell-widgets.service || true
      '';
    };

    lightModeScripts = {
      helix = ''
        ${coreutils}/bin/install -m 644 ${helixTheme "light"} "${helixAutoTheme}"
      '';
      alacritty = ''
        ${coreutils}/bin/install -m 644 ${alacrittyColors.light} "${alacrittyColorsPath}"
      '';
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
        ${dconfExe} write /org/gnome/desktop/interface/gtk-theme "'adw-gtk3'"
        ${dconfExe} write /org/gnome/desktop/interface/icon-theme "'Papirus-Light'"
      '';
      mako = ''
        ${pkgs.mako}/bin/makoctl mode -a light
      '';
      quickshell-theme = ''
        ${treeLink} "${config.xdg.configHome}/quickshell/widgets-light" "${config.xdg.configHome}/quickshell/widgets"
        ${pkgs.systemd}/bin/systemctl --user restart quickshell-widgets.service || true
      '';
    };
  };
}
