{ pkgs, upkgs, config, lib, ... }:

let
  colors = config.lib.stylix.colors;

  laserColor = if config.stylix.polarity == "light" then "#FFFFFF" else "#000000";

  # Lockscreen-only theming — reuses the same @token@ substitution the file
  # already uses for the bar, but keyed off the shared palette instead of
  # config.lib.stylix.colors, and scoped to just the lock component. Do not
  # extend this to shell.qml/Wallpaper/Clock/Music/Calendar/RevealMask/
  # LaserBar — those are the in-progress bar and are out of scope.
  lockThemeColors = import ../../../lib/theme-colors.nix;

  withLockThemeColors = c: laserColorVariant: builtins.replaceStrings
    [
      "@cardBg@"
      "@cardBorder@"
      "@clockColor@"
      "@dateColor@"
      "@dividerColor@"
      "@tempColor@"
      "@lockBg@"
      "@systemctlBin@"
      "@lockscreenImage@"
      "@laserColor@"
      "@greenColor@"
      "@redColor@"
    ]
    [
      "#B3${c.base00}"
      "#33${c.base05}"
      "#FF${c.base05}"
      "#CC${c.base04}"
      "#22${c.base03}"
      "#FF${c.base0D}"
      "#FF${c.base00}"
      "${pkgs.systemd}/bin/systemctl"
      "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png"
      laserColorVariant
      "#FF${c.base0B}"
      "#FF${c.base08}"
    ];

  lockVariant = variant: lockComponent: {
    text = withLockThemeColors lockThemeColors.${variant}
      (if variant == "light" then "#FFFFFF" else "#000000")
      (builtins.readFile lockComponent);
  };

  withThemeColors = builtins.replaceStrings
    [
      "@cardBg@"
      "@cardBorder@"
      "@clockColor@"
      "@dateColor@"
      "@dividerColor@"
      "@tempColor@"
      "@lockBg@"
      "@systemctlBin@"
      "@lockscreenImage@"
      "@laserColor@"
    ]
    [
      "#B3${colors.base00}"
      "#33${colors.base05}"
      "#FF${colors.base05}"
      "#CC${colors.base04}"
      "#22${colors.base03}"
      "#FF${colors.base0D}"
      "#FF${colors.base00}"
      "${pkgs.systemd}/bin/systemctl"
      "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png"
      laserColor
    ];

  themedQmlFile = path: {
    text = withThemeColors (builtins.readFile path);
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
    "quickshell/widgets/components/Lock-dark.qml" = lockVariant "dark" ./components/LockDark.qml;
    "quickshell/widgets/components/Lock-light.qml" = lockVariant "light" ./components/LockLight.qml;
    "quickshell/widgets/components/RevealMask.qml" = themedQmlFile ./components/RevealMask.qml;
    "quickshell/widgets/components/LaserBar.qml" = themedQmlFile ./components/LaserBar.qml;
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
