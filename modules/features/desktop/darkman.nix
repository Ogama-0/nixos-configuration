{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.desktop.darkman.enable =
        lib.mkEnableOption "the dark/light switch that rewrites app themes at sunrise and sunset";
    };
in
{
  flake.featureModules.nixos.darkman = sharedOptions;

  flake.featureModules.home.darkman =
    {
      pkgs,
      lpkgs,
      lib,
      config,
      ...
    }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.desktop.darkman.enable (
        let
          dconfExe = "${pkgs.dconf}/bin/dconf";

          alacrittyColorsPath = "${config.xdg.configHome}/alacritty/colors.toml";
          alacrittyColors = import ../../../lib/alacritty-colors.nix { inherit pkgs; };
          treeLink = import ../../../lib/quickshell-tree-link.nix { inherit pkgs; };

          helixAutoTheme = "${config.xdg.configHome}/helix/themes/auto.toml";
          helixTheme = import ../../../lib/helix-auto-theme.nix { inherit pkgs; };

          # helix re-reads its config and theme on SIGUSR1 (verified: it logs
          # "failed to load theme" when sent one after the theme file is changed).
          # Without this an open editor keeps the old theme while the terminal's ANSI
          # palette flips underneath it, which renders as badly mismatched colours.
          #
          # The matcher must cover `.hx-wrapped`: the nixpkgs wrapper means comm is
          # NOT `hx`, so a bare `pkill -x hx` silently matches nothing - the same
          # truncated-comm trap documented in docs/adding-a-server-service.md.
          # `|| true` because no editor running is the normal case, and darkman must
          # not report a failed transition for it.
          helixReload = ''
            ${pkgs.procps}/bin/pkill -x -USR1 '(\.hx-wrapped|hx)' || true
          '';

          zellijAutoTheme = "${config.xdg.configHome}/zellij/themes/auto.kdl";
          zellijThemes = import ../../../lib/zellij-theme.nix { inherit pkgs; };

          # zellij paints its own chrome in true colour, so unlike the other TUIs it
          # does not follow alacritty's ANSI palette - it has to be told, and twice:
          #
          #   * auto.kdl is the theme *new* sessions start in. zellij decides that for
          #     itself by asking the terminal for its background with OSC 11, but
          #     falls back to its own built-in (radioactive green) theme whenever no
          #     answer arrives - see lib/zellij-theme.nix.
          #   * the `action` below is for the sessions already running.
          #
          # `action` targets a single session, so every live one gets its own call.
          # `list-sessions` also lists dead-but-resurrectable sessions - those have no
          # server to talk to, hence the EXITED filter - and exits non-zero when there
          # are none at all, which is the normal case. A session started before the
          # last switch still holds the old config and will refuse the switch, hence
          # `|| true`.
          zellijTheme = mode: ''
            ${coreutils}/bin/install -m 644 ${zellijThemes.auto mode} "${zellijAutoTheme}"
            ${pkgs.zellij}/bin/zellij list-sessions -n 2>/dev/null \
              | ${pkgs.gnugrep}/bin/grep -v EXITED \
              | ${coreutils}/bin/cut -d' ' -f1 \
              | while read -r session; do
                  ${pkgs.zellij}/bin/zellij --session "$session" action set-${mode}-theme || true
                done
          '';

          # Relinking the tree is always safe: it only changes which QML the NEXT
          # start reads. The restart is not, and that guard is the whole point of
          # this helper.
          #
          # quickshell-widgets hosts the session lock (components/LockDark.qml,
          # wired in shell.qml). Killing it while that lock is up destroys the
          # ext-session-lock surface, and the protocol forbids sway from
          # unlocking on client death - so sway falls back to painting a solid
          # red screen that takes no input and cannot be authenticated. The only
          # way out of that is a reboot.
          #
          # Which is not hypothetical: it is what happened on every resume that
          # crossed sunrise or sundown. The lid-close `before-sleep` locks the
          # session, darkman wakes on resume, decides the mode changed, and
          # restarts the process holding the lock. That is also why it read as
          # intermittent - resumes inside the same mode never ran this script.
          #
          # Nothing is lost by skipping the restart. The relink has already
          # happened, and the lock restarts the shell itself 500ms after a
          # successful unlock (postUnlockRestart), which picks up the
          # newly-linked tree. The cost is a lock surface in the old palette
          # until then.
          #
          # Fail CLOSED: restart only on a positive, exact "false". A dead shell
          # or any unexpected output leaves the restart undone, which costs a
          # stale palette until the next transition. Guessing the other way costs
          # a reboot, and that asymmetry is what picks the default.
          quickshellTheme = variant: ''
            ${treeLink} "${config.xdg.configHome}/quickshell/widgets-${variant}" "${config.xdg.configHome}/quickshell/widgets"

            if [ "$(${lpkgs.quickshell-multimedia}/bin/quickshell ipc -c widgets call lock isLocked 2>/dev/null)" = "false" ]; then
              ${pkgs.systemd}/bin/systemctl --user restart quickshell-widgets.service || true
            fi
          '';

          bashExe = "${pkgs.bash}/bin/bash";
          coreutils = pkgs.coreutils;

          # Shared with the greeter (pkgs/greetd-proxy), which has to make the same
          # sunrise/sunset decision before any user session exists.
          tzTable = import ../../../lib/timezone-coords.nix;
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
          home.activation.darkmanTimezoneSync =
            lib.hm.dag.entryAfter [ "linkGeneration" "quickshellThemeTree" ]
              ''
                ${bashExe} ${syncScript}
              '';

          # The GTK themes the scripts below select between. Installed here rather
          # than in display/gtk.nix because that module is shared with `epita`, which
          # has no darkman and would gain them for nothing.
          home.packages = with pkgs; [
            adw-gtk3
            papirus-icon-theme
          ];

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
              zellij = zellijTheme "dark";
              helix = ''
                ${coreutils}/bin/install -m 644 ${helixTheme "dark"} "${helixAutoTheme}"
                ${helixReload}
              '';
              alacritty = ''
                ${coreutils}/bin/install -m 644 ${alacrittyColors.dark} "${alacrittyColorsPath}"
              '';
              gtk-theme = ''
                ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
                ${dconfExe} write /org/gnome/desktop/interface/gtk-theme "'adw-gtk3-dark'"
                ${dconfExe} write /org/gnome/desktop/interface/icon-theme "'Papirus-Dark'"
              '';
              quickshell-theme = quickshellTheme "dark";
            };

            lightModeScripts = {
              zellij = zellijTheme "light";
              helix = ''
                ${coreutils}/bin/install -m 644 ${helixTheme "light"} "${helixAutoTheme}"
                ${helixReload}
              '';
              alacritty = ''
                ${coreutils}/bin/install -m 644 ${alacrittyColors.light} "${alacrittyColorsPath}"
              '';
              gtk-theme = ''
                ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
                ${dconfExe} write /org/gnome/desktop/interface/gtk-theme "'adw-gtk3'"
                ${dconfExe} write /org/gnome/desktop/interface/icon-theme "'Papirus-Light'"
              '';
              quickshell-theme = quickshellTheme "light";
            };
          };
        }
      );
    };
}
