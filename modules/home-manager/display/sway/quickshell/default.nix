{ cfg, pkgs, upkgs, config, lib, ... }:

let
  colors = config.lib.stylix.colors;

  laserColor = if config.stylix.polarity == "light" then "#FFFFFF" else "#000000";

  # Horizon puts teal at base0C in the dark scheme but base0E in the light one,
  # and base0C in light is a red-orange - so no single base16 slot can mean
  # "up" in both. Selected by polarity instead, exactly like laserColor above.
  # The light teal is the darker #1D8991 so a filled band still clears 3:1
  # against the light ground.
  isLight = config.stylix.polarity == "light";

  statusColors = {
    upColor = if isLight then "#FF1D8991" else "#FF24A8B4";
    degradedColor = if isLight then "#FFF6661E" else "#FFEFB993";
    downColor = if isLight then "#FFDA103F" else "#FFE93C58";
  };

  # Built from cfg.server.domain so the tailnet hostnames are never hardcoded
  # in QML. cfg-perso embeds the server profile under .server (host/profiles.nix).
  statusApiUrl = "http://status.tail.${cfg.server.domain}/api/v1/endpoints/statuses";
  metricsApiUrl = "http://metrics.tail.${cfg.server.domain}/api/v1/query";

  # Lockscreen-only theming — reuses the same @token@ substitution the file
  # already uses for the bar, but keyed off the shared palette instead of
  # config.lib.stylix.colors, and scoped to just the lock component. Do not
  # extend this to shell.qml/Wallpaper/Clock/Music/Calendar/RevealMask/
  # LaserBar — those are the in-progress bar and are out of scope.
  lockThemeColors = import ../../../../lib/theme-colors.nix;

  qmlTheme = import ../../../../lib/qml-theme.nix;

  systemctlBin = "${pkgs.systemd}/bin/systemctl";
  corptaFontPath = "${config.home.homeDirectory}/nixos-configuration/assets/fonts/Corpta-DEMO.otf";

  barTheme = qmlTheme ({
    inherit colors laserColor systemctlBin corptaFontPath;
    inherit statusApiUrl metricsApiUrl;
    lockscreenImage = "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png";
  } // statusColors);

  themedQmlFile = path: {
    text = barTheme (builtins.readFile path);
  };

  # Each variant gets its own lockscreen artwork: the dark variant uses the
  # Arcane/Jinx piece (see LockDark.qml), the light variant keeps the
  # original Nausicaa/snow treatment (see LockLight.qml) - they're
  # deliberately different designs, not the same skin recolored.
  lockVariant = variant: lockComponent: image: {
    text = qmlTheme {
      inherit systemctlBin corptaFontPath;
      colors = lockThemeColors.${variant};
      laserColor = if variant == "light" then "#FFFFFF" else "#000000";
      lockscreenImage = image;
    } (builtins.readFile lockComponent);
  };
in
{
  home.packages = [
    upkgs.quickshell
    pkgs.curl
    pkgs.cava
    pkgs.imagemagick
  ];

  xdg.configFile = {
    "quickshell/widgets/cava.conf".text = ''
      [general]
      bars = 20
      framerate = 60
      sensitivity = 195

      [input]
      method = pipewire
      source = auto

      [smoothing]
      noise_reduction = 30

      [output]
      method = raw
      raw_target = /dev/stdout
      data_format = ascii
      ascii_max_range = 100
      bar_delimiter = 59
      frame_delimiter = 10
    '';

    "quickshell/widgets/shell.qml" = themedQmlFile ./shell.qml;
    "quickshell/widgets/components/Wallpaper.qml" = themedQmlFile ./components/Wallpaper.qml;
    "quickshell/widgets/components/Clock.qml" = themedQmlFile ./components/Clock.qml;
    "quickshell/widgets/components/Music.qml" = themedQmlFile ./components/Music.qml;
    "quickshell/widgets/components/Calendar.qml" = themedQmlFile ./components/Calendar.qml;
    "quickshell/widgets/components/Lock-dark.qml" = lockVariant "dark" ./components/LockDark.qml
      "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/dark-lockscreen-arcane-jinx.jpeg";
    "quickshell/widgets/components/Lock-light.qml" = lockVariant "light" ./components/LockLight.qml
      "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png";
    "quickshell/widgets/components/RevealMask.qml" = themedQmlFile ./components/RevealMask.qml;
    "quickshell/widgets/components/GlassPill.qml" = themedQmlFile ./components/GlassPill.qml;
    "quickshell/widgets/components/ColorUtils.qml" = themedQmlFile ./components/ColorUtils.qml;
    "quickshell/widgets/components/BeamSide.qml" = themedQmlFile ./components/BeamSide.qml;
    "quickshell/widgets/components/CollisionEffects.qml" = themedQmlFile ./components/CollisionEffects.qml;
    "quickshell/widgets/components/ClockModule.qml" = themedQmlFile ./components/ClockModule.qml;
    "quickshell/widgets/components/LaserBar.qml" = themedQmlFile ./components/LaserBar.qml;
    "quickshell/widgets/components/StatusModel.qml" = themedQmlFile ./components/StatusModel.qml;
    "quickshell/widgets/components/Sparkline.qml" = themedQmlFile ./components/Sparkline.qml;
    "quickshell/widgets/components/StatusPanel.qml" = themedQmlFile ./components/StatusPanel.qml;
  };

  home.activation.quickshellLockDefault = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/quickshell/widgets/components/Lock-dark.qml" "${config.xdg.configHome}/quickshell/widgets/components/Lock.qml"
  '';

  systemd.user.services.quickshell-widgets = {
    Unit = {
      Description = "Quickshell desktop widgets (clock, Paris weather, media player)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${upkgs.quickshell}/bin/quickshell -c widgets";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
