{ pkgs, upkgs, config, ... }:

let
  colors = config.lib.stylix.colors;

  # Two independent lockscreen designs; stylix.polarity picks which one
  # gets installed as Lock.qml (see ../../../stylix.nix for where the host
  # sets its polarity).
  lockComponent =
    if config.stylix.polarity == "dark"
    then ./components/LockDark.qml
    else ./components/LockLight.qml;

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
    "quickshell/widgets/components/Lock.qml" = themedQmlFile lockComponent;
  };

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
