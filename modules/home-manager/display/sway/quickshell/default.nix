{ pkgs, upkgs, config, ... }:

let
  colors = config.lib.stylix.colors;

  withThemeColors = builtins.replaceStrings
    [
      "@cardBg@"
      "@cardBorder@"
      "@clockColor@"
      "@dateColor@"
      "@dividerColor@"
      "@tempColor@"
    ]
    [
      "#B3${colors.base00}"
      "#33${colors.base05}"
      "#FF${colors.base05}"
      "#CC${colors.base04}"
      "#22${colors.base03}"
      "#FF${colors.base0D}"
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
  ];

  xdg.configFile = {
    "quickshell/widgets/cava.conf".text = ''
      [general]
      bars = 20
      framerate = 60

      [input]
      method = pipewire
      source = auto

      [output]
      method = raw
      raw_target = /dev/stdout
      data_format = ascii
      ascii_max_range = 100
      bar_delimiter = 59
      frame_delimiter = 10
    '';

    "quickshell/widgets/shell.qml" = themedQmlFile ./shell.qml;
    "quickshell/widgets/components/Clock.qml" = themedQmlFile ./components/Clock.qml;
    "quickshell/widgets/components/Music.qml" = themedQmlFile ./components/Music.qml;
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
