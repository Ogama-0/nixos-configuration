# Graphical login for the personal profile: greetd runs sway, sway runs a
# Quickshell greeter that mirrors the lockscreen design. See
# docs/superpowers/specs/2026-10-06-quickshell-greeter-design.md
#
# Everything the greeter touches resolves to the Nix store or /etc/greeter.
# The greeter user must never depend on reading /home/ogama.
{ pkgs, lpkgs, upkgs, lib, ... }:

let
  qmlTheme = import ../lib/qml-theme.nix;
  palettes = import ../lib/theme-colors.nix;

  greetdProxy = "${lpkgs.greetd-proxy}/bin/greetd-proxy";
  swayBin = "${pkgs.sway}/bin/sway";
  swaymsgBin = "${pkgs.sway}/bin/swaymsg";
  systemctlBin = "${pkgs.systemd}/bin/systemctl";

  darkImage = ../../assets/lockscreen/dark-lockscreen-arcane-jinx.jpeg;
  lightImage = ../../assets/lockscreen/nausicaa.png;
  corptaFont = ../../assets/fonts/Corpta-DEMO.otf;

  # Greeter-only tokens, on top of the shared palette substitution.
  withGreeterBins = builtins.replaceStrings
    [ "@greetdProxyBin@" "@swayBin@" ]
    [ greetdProxy swayBin ];

  themeGreeter = variant: image: path:
    withGreeterBins (qmlTheme {
      colors = palettes.${variant};
      laserColor = if variant == "light" then "#FFFFFF" else "#000000";
      lockscreenImage = "${image}";
      inherit systemctlBin;
      corptaFontPath = "${corptaFont}";
    } (builtins.readFile path));

  # GreetdSession carries no palette tokens, only the two binary paths, so
  # one copy serves both variants.
  greetdSessionQml = themeGreeter "dark" darkImage ../qml/components/GreetdSession.qml;

  # If quickshell cannot start, fall back to a text greeter rather than
  # leaving the machine with no way in. This is the primary lockout guard.
  launcher = pkgs.writeShellScript "greeter-launch" ''
    VARIANT=$(${greetdProxy} --theme || echo dark)
    case "$VARIANT" in
      light) SURFACE=/etc/greeter/GreeterLight.qml ;;
      *)     SURFACE=/etc/greeter/GreeterDark.qml ;;
    esac

    if ! ${upkgs.quickshell}/bin/quickshell -p "$SURFACE"; then
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
    "greeter/GreeterDark.qml".text = themeGreeter "dark" darkImage ../qml/GreeterDark.qml;
    "greeter/GreeterLight.qml".text = themeGreeter "light" lightImage ../qml/GreeterLight.qml;
    "greeter/components/GreetdSession.qml".text = greetdSessionQml;
    "greeter/sway.conf".source = swayConf;
  };

  # The greeter user cannot see home-manager's font packages.
  fonts.packages = [
    lpkgs.corpta-font
    lpkgs.orbitron-font
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
