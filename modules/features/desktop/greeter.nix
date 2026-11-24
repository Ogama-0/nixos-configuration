# Graphical login for the personal profile: greetd runs sway, sway runs a
# Quickshell greeter that mirrors the lockscreen design. See
# docs/superpowers/specs/2026-10-06-quickshell-greeter-design.md
#
# Everything the greeter touches resolves to the Nix store or /etc/greeter.
# The greeter user must never depend on reading /home/ogama.
{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { config, lib, ... }:
    {
      options.ogama.desktop.greeter.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.ogama.desktop.sway.enable;
        defaultText = lib.literalExpression "config.ogama.desktop.sway.enable";
        description = "the greetd greeter and its themed QML";
      };
    };
in
{
  flake.featureModules.nixos.greeter =
    {
      config,
      pkgs,
      lpkgs,
      upkgs,
      lib,
      ...
    }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.desktop.greeter.enable (
        let
          qmlTheme = import ../../../lib/qml-theme.nix;
          palettes = import ../../../lib/theme-colors.nix;

          # Instrumentation for the greeter, which can log nowhere else: it is
          # a Wayland surface owned by a user with no home directory, started
          # by a compositor started by greetd. Records message types, timings
          # and password *lengths* - never a password - to
          # /tmp/greeter-trace.log, plus quickshell's own stderr to
          # /tmp/greeter-quickshell.log.
          #
          # ON, and it has to stay on until the greeter is reliable. It was
          # turned off on 2026-11-23 because it had answered the "first login
          # is always rejected" question, and the greeter failed to come up
          # twice within the hour with nothing recorded either time - the
          # failure that is actually happening is the one this would show.
          # See docs/superpowers/specs/2026-11-23-greeter-output-race.md.
          debugTrace = true;

          greetdProxy = "${lpkgs.greetd-proxy}/bin/greetd-proxy";
          # The greeter itself runs plain sway: it shows one fullscreen Quickshell
          # surface, so swayfx's effects would buy nothing on the one code path that
          # must never fail to come up.
          swayBin = "${pkgs.sway}/bin/sway";

          # The *session* is swayfx - ~/.config/sway/config carries swayfx-only
          # directives (corner_radius, shadows, ...) that plain sway rejects with a
          # red "there are errors in your config file" banner on every login.
          # home-manager writes that config and puts swayfx on PATH, but nothing
          # execs it: greetd starts the session by absolute store path, right here.
          sessionBin = "${import ../../../lib/swayfx.nix pkgs}/bin/sway";
          swaymsgBin = "${pkgs.sway}/bin/swaymsg";
          # Draws on sway's own output, which is the only surface the user can
          # see when the greeter has failed - see the fallback in `launcher`.
          swaynagBin = "${pkgs.sway}/bin/swaynag";
          systemctlBin = "${pkgs.systemd}/bin/systemctl";

          darkImage = ../../../assets/lockscreen/dark-lockscreen-arcane-jinx.jpeg;
          lightImage = ../../../assets/lockscreen/nausicaa.png;
          corptaFont = ../../../assets/fonts/Corpta-DEMO.otf;

          # Greeter-only tokens, on top of the shared palette substitution.
          withGreeterBins =
            builtins.replaceStrings
              [ "@greetdProxyBin@" "@sessionBin@" ]
              [ greetdProxy sessionBin ];

          themeGreeter =
            variant: image: path:
            withGreeterBins (
              qmlTheme {
                colors = palettes.${variant};
                laserColor = if variant == "light" then "#FFFFFF" else "#000000";
                lockscreenImage = "${image}";
                inherit systemctlBin;
                corptaFontPath = "${corptaFont}";
              } (builtins.readFile path)
            );

          # GreetdSession carries no palette tokens, only the two binary paths, so
          # one copy serves both variants.
          greetdSessionQml = themeGreeter "dark" darkImage ../../../qml/components/GreetdSession.qml;

          # If quickshell cannot start, fall back to a text greeter rather than
          # leaving the machine with no way in. This is the primary lockout guard.
          #
          # The exit status cannot be the trigger: greetd kills the greeter the
          # moment it honours start_session, so a *successful* login also ends with
          # quickshell exiting non-zero. Keying off that put agreety on VT1 for a
          # moment on every single login (it then crashed as the session took over).
          # greetd-proxy drops the marker just before it relays start_session, so
          # its absence means no session was ever requested - the one case the
          # fallback is for.
          launcher = pkgs.writeShellScript "greeter-launch" ''
                VARIANT=$(${greetdProxy} --theme || echo dark)
                case "$VARIANT" in
                  light) SURFACE=/etc/greeter/GreeterLight.qml ;;
                  *)     SURFACE=/etc/greeter/GreeterDark.qml ;;
                esac

                GREETD_STARTED_MARKER="$(${pkgs.coreutils}/bin/mktemp -d)/started"
                export GREETD_STARTED_MARKER
            ${lib.optionalString debugTrace ''
              GREETD_TRACE=/tmp/greeter-trace.log
              export GREETD_TRACE
              echo "-- greeter-launch starting surface $SURFACE" >> "$GREETD_TRACE"
            ''}
                # Do not start quickshell until sway actually has an output.
                #
                # This is the "greeter never appeared" failure, and it is a
                # race, which is why it came and went. sway runs exec_always
                # as soon as it has read its config - which can be before the
                # eDP output is enabled. quickshell starts, Qt reports zero
                # screens and invents a placeholder, the bare PanelWindow in
                # Greeter{Dark,Light}.qml binds to it, and when the real
                # output turns up the placeholder's wl_output global is gone:
                #
                #   qt.qpa.wayland: There are no outputs - creating placeholder screen
                #   wl_registry#2: error 0: global wl_output (60) is unavailable
                #   WARN: The Wayland connection experienced a fatal error: Protocol error
                #
                # sway's own IPC is the authority on when its output is up, so
                # ask it rather than sleeping a guessed interval. Bounded at
                # 5s so a genuinely headless boot still reaches the fallback
                # below instead of spinning here forever; in practice the
                # output is there within a few hundred milliseconds.
                tries=0
                while [ "$tries" -lt 100 ]; do
                  if ${swaymsgBin} -t get_outputs 2>/dev/null \
                       | ${pkgs.gnugrep}/bin/grep -q '"active": true'; then
                    break
                  fi
                  tries=$((tries + 1))
                  ${pkgs.coreutils}/bin/sleep 0.05
                done
            ${lib.optionalString debugTrace ''
              echo "-- greeter-launch: output ready after $tries tries" >> "$GREETD_TRACE"
            ''}
                ${upkgs.quickshell}/bin/quickshell -p "$SURFACE" ${lib.optionalString debugTrace ">> /tmp/greeter-quickshell.log 2>&1"} || true

                if [ ! -e "$GREETD_STARTED_MARKER" ]; then
                  # Say so ON SCREEN first. agreety writes to the VT, and sway
                  # is holding that VT in graphics mode, so the text greeter
                  # is invisible - which is why this path looked like a black
                  # screen for five and a half minutes on 2026-11-22 and again
                  # twice on 2026-11-24. swaynag draws on sway's own output,
                  # so it is the one thing here the user can actually see.
                  ${swaynagBin} -t warning -m \
                    "Greeter failed to start. Press Ctrl+Alt+F2 for a console login." \
                    >/dev/null 2>&1 || true
                  exec ${pkgs.greetd}/bin/agreety --cmd ${swayBin}
                fi
          '';

          swayConf = pkgs.writeText "greeter-sway.conf" ''
            # Mirrors modules/home-manager/keyboard.nix so Caps behaves the same at
            # the login screen as it does inside the session.
            input "type:keyboard" {
                xkb_options caps:escape
            }

            # The greeter owns the whole screen; nothing else should decorate it.
            default_border none

            # When the greeter exits - either because greetd is starting the real
            # session, or because the agreety fallback finished - this sway instance
            # has nothing left to do, so tear it down instead of leaving an empty
            # compositor holding VT1.
            exec_always "${launcher}; ${swaymsgBin} exit"
          '';
        in
        {
          environment.etc = {
            "greeter/GreeterDark.qml".text = themeGreeter "dark" darkImage ../../../qml/GreeterDark.qml;
            "greeter/GreeterLight.qml".text = themeGreeter "light" lightImage ../../../qml/GreeterLight.qml;
            "greeter/components/GreetdSession.qml".text = greetdSessionQml;
            "greeter/sway.conf".source = swayConf;
          };

          # The greeter user cannot see home-manager's font packages.
          fonts.packages = [
            lpkgs.corpta-font
            lpkgs.orbitron-font
            pkgs.nunito
            pkgs.inter
          ];

          # No `vt` option: current nixpkgs fixes greetd to VT1 and errors if it is
          # set. That is what this design wanted anyway - Ctrl+Alt+F2 stays a plain
          # getty, which is the last-resort way back in if the greeter breaks.
          services.greetd = {
            enable = true;
            settings.default_session = {
              command = "${swayBin} -c /etc/greeter/sway.conf";
              user = "greeter";
            };
          };

          # Power controls on the greeter surface.
          security.polkit.extraConfig = ''
            polkit.addRule(function(action, subject) {
              if (subject.user == "greeter" &&
                  (action.id == "org.freedesktop.login1.power-off" ||
                   action.id == "org.freedesktop.login1.reboot" ||
                   action.id == "org.freedesktop.login1.suspend")) {
                return polkit.Result.YES;
              }
            });
          '';
        }
      );
    };

  flake.featureModules.home.greeter = sharedOptions;
}
