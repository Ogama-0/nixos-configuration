{ cfg, pkgs, upkgs, config, lib, ... }:

let
  allColors = import ../../../../lib/theme-colors.nix;

  # Semantic status colours, per variant. They are NOT one base16 slot: the
  # two palettes disagree about where each hue lives, and several light slots
  # fail their contrast floors outright. The measured values live in
  # modules/lib/palette.nix under `<mode>.status` - edit them there.
  #
  # The alpha prefixes are applied here because QML wants #AARRGGBB: FF for
  # the opaque bands, CC for the muted light column (base05 at 80%).
  palette = import ../../../../lib/palette.nix;

  statusColorsFor = variant:
    let st = palette.${variant}.status;
        opaque = c: "#FF" + builtins.substring 1 6 c;
    in {
      upColor = opaque st.up;
      degradedColor = opaque st.degraded;
      downColor = opaque st.down;
      mutedColor =
        if variant == "light"
        then "#CC" + builtins.substring 1 6 st.muted
        else opaque st.muted;
    };

  # The capsule is a light plate with a near-black outline in both variants,
  # which means reading from opposite ends of the palette depending on polarity
  # rather than from one fixed slot.
  capsuleColorsFor = variant:
    let c = allColors.${variant}; in
    if variant == "light"
    then { capsuleFill = "#F2${c.base00}"; capsuleInk = "#FF${c.base05}"; }
    else { capsuleFill = "#F2${c.base05}"; capsuleInk = "#FF${c.base00}"; };

  # Messages' identity-hue pool: one accent slot per contact, hashed from the
  # phone number so a person keeps one colour forever.
  #
  # Not the same slots in both variants. Horizon light's base0A is #FBE0D9 -
  # near-white - and initials painted in it disappear into the cream sheet, so
  # light gets seven slots and dark gets eight. Dropping it from both instead
  # would cost dark a perfectly good yellow for a problem it does not have.
  msgHuesFor = variant:
    let c = allColors.${variant};
        opaque = v: "#FF" + v;
        slots = if variant == "light"
                then [ c.base08 c.base09 c.base0B c.base0C c.base0D c.base0E c.base0F ]
                else [ c.base08 c.base09 c.base0A c.base0B c.base0C c.base0D c.base0E c.base0F ];
    in { msgHues = builtins.concatStringsSep "," (map opaque slots); };

  # The outgoing bubble, and the ink on it. base0D is the slot the bar already
  # treats as THE UI accent; base0B (@greenColor@) is this panel's "a thing is
  # on" colour and would make every message you sent read as a status light.
  #
  # In light that lands on #DA103F, a crimson rather than a blue. That is
  # Horizon light, not a mistake - the palette is not a recolour of the dark
  # set and no single slot means "blue" in both.
  msgAccentFor = variant:
    let c = allColors.${variant}; in {
      msgAccent = "#FF" + c.base0D;
      msgAccentInk = if variant == "light"
                     then "#FF" + c.base07
                     else "#FF" + c.base00;
    };

  # Ink on an accent (base0B) fill: base00 in dark, base07 in light. Light's
  # base00 is the cream ground, so an icon in it would vanish into the green.
  onAccentInkFor = variant:
    let c = allColors.${variant}; in
    if variant == "light" then "#FF${c.base07}" else "#FF${c.base00}";

  # Built from the profile so the tailnet hostnames are never hardcoded in QML.
  #
  # The doubled `.server.server` is not a typo. host/profiles.nix builds every
  # profile as `base // (extra base)`, and base sets `server.domain`. cfg-perso's
  # extra then sets `server = cfg-server`, which *replaces* that whole attrset
  # rather than merging into it - so from the personal profile the domain lives
  # at cfg.server.server.domain, one level deeper than the server-side modules'
  # cfg.server.domain (where cfg is already cfg-server and base's value is
  # intact). Every other consumer in the repo is server-only, so this module is
  # the first to hit it.
  serverDomain = cfg.server.server.domain;

  statusApiUrl = "http://status.tail.${serverDomain}/api/v1/endpoints/statuses";
  metricsApiUrl = "http://metrics.tail.${serverDomain}/api/v1/query";

  # Lockscreen theming reuses the same @token@ substitution and the same
  # `allColors` palette as the bar; what differs is that each variant renders
  # its own component and artwork (see lockFor below).
  qmlTheme = import ../../../../lib/qml-theme.nix;

  treeLink = import ../../../../lib/quickshell-tree-link.nix { inherit pkgs; };

  systemctlBin = "${pkgs.systemd}/bin/systemctl";
  # The session's own sway, not pkgs.sway, so this pulls nothing extra into
  # the closure. See modules/lib/swayfx.nix.
  swaymsgBin = "${import ../../../../lib/swayfx.nix pkgs}/bin/swaymsg";
  corptaFontPath = "${config.home.homeDirectory}/nixos-configuration/assets/fonts/Corpta-DEMO.otf";

  themeFor = variant: qmlTheme ({
    colors = allColors.${variant};
    laserColor = if variant == "light" then "#FFFFFF" else "#000000";
    wallpaperDirs = "${variant} both";
    inherit systemctlBin swaymsgBin corptaFontPath statusApiUrl metricsApiUrl;
    lockscreenImage = "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png";
    onAccentInk = onAccentInkFor variant;
    whereAmIBin = "${pkgs.geoclue2}/libexec/geoclue-2.0/demos/where-am-i";
    # Both variants are nearly opaque, and dark learned this the same way
    # @cardBg@'s consumers did. At 80% a bright window underneath - a
    # terminal, a white page - read straight through the panel and sat
    # behind the notification text. The beam showing through was never worth
    # that; what sells the glass is the border and the sheen, not the alpha.
    #
    # base01, not base00, in dark. base00 IS black, and a 94%-black sheet on
    # a black wallpaper has no edges - the panel vanished and left its own
    # internal dividers floating in space. base01 is the next step up the
    # ramp and reads as a surface on any ground.
    sheetBg = if variant == "light"
              then "#F2${allColors.light.base00}"
              else "#EF${allColors.dark.base00}";
  } // statusColorsFor variant // capsuleColorsFor variant
    // msgHuesFor variant // msgAccentFor variant);

  themedQmlFile = variant: path: {
    text = themeFor variant (builtins.readFile path);
  };

  lockVariant = variant: lockComponent: image: {
    text = qmlTheme {
      inherit systemctlBin corptaFontPath;
      colors = allColors.${variant};
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
    # Messages shells out to both, and MobileModel.sendFile has been relying
    # on zenity being here by accident since it was written. Declared now:
    # a file picker that is missing fails as a silently cancelled dialog,
    # which looks exactly like the user changing their mind.
    pkgs.zenity
    pkgs.wl-clipboard
  ];

  xdg.configFile =
    let
      cavaConf = ''
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

      # Each variant gets its own lockscreen artwork: dark uses the Arcane/Jinx
      # piece (see LockDark.qml), light keeps the original Nausicaa/snow
      # treatment (see LockLight.qml) - they are deliberately different
      # designs, not the same skin recoloured.
      lockFor = {
        dark = lockVariant "dark" ./components/LockDark.qml
          "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/dark-lockscreen-arcane-jinx.jpeg";
        light = lockVariant "light" ./components/LockLight.qml
          "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png";
      };

      # Music.qml resolves cava as Quickshell.shellDir + "/cava.conf", so each
      # tree needs its own copy; shellDir makes that automatic.
      treeFor = variant:
        let d = "quickshell/widgets-${variant}"; in {
          "${d}/cava.conf".text = cavaConf;
          "${d}/shell.qml" = themedQmlFile variant ./shell.qml;
          "${d}/components/Lock.qml" = lockFor.${variant};
          "${d}/components/Wallpaper.qml" = themedQmlFile variant ./components/Wallpaper.qml;
          "${d}/components/Clock.qml" = themedQmlFile variant ./components/Clock.qml;
          "${d}/components/Music.qml" = themedQmlFile variant ./components/Music.qml;
          "${d}/components/MprisModel.qml" = themedQmlFile variant ./components/MprisModel.qml;
          "${d}/components/RemoteSpectrum.qml" = themedQmlFile variant ./components/RemoteSpectrum.qml;
          "${d}/components/RemoteBadge.qml" = themedQmlFile variant ./components/RemoteBadge.qml;
          "${d}/components/Calendar.qml" = themedQmlFile variant ./components/Calendar.qml;
          "${d}/components/RevealMask.qml" = themedQmlFile variant ./components/RevealMask.qml;
          "${d}/components/GlassPill.qml" = themedQmlFile variant ./components/GlassPill.qml;
          "${d}/components/ColorUtils.qml" = themedQmlFile variant ./components/ColorUtils.qml;
          "${d}/components/BarShell.qml" = themedQmlFile variant ./components/BarShell.qml;
          "${d}/components/BarGroup.qml" = themedQmlFile variant ./components/BarGroup.qml;
          "${d}/components/BarSlots.qml" = themedQmlFile variant ./components/BarSlots.qml;
          "${d}/components/WorkspaceIcon.qml" = themedQmlFile variant ./components/WorkspaceIcon.qml;
          "${d}/components/WorkspaceWidget.qml" = themedQmlFile variant ./components/WorkspaceWidget.qml;
          "${d}/components/WifiWidget.qml" = themedQmlFile variant ./components/WifiWidget.qml;
          "${d}/components/BarButton.qml" = themedQmlFile variant ./components/BarButton.qml;
          "${d}/components/MusicWidget.qml" = themedQmlFile variant ./components/MusicWidget.qml;
          "${d}/components/BeamSide.qml" = themedQmlFile variant ./components/BeamSide.qml;
          "${d}/components/CollisionEffects.qml" = themedQmlFile variant ./components/CollisionEffects.qml;
          "${d}/components/ClockWidget.qml" = themedQmlFile variant ./components/ClockWidget.qml;
          "${d}/components/LaserBar.qml" = themedQmlFile variant ./components/LaserBar.qml;
          "${d}/components/StatusModel.qml" = themedQmlFile variant ./components/StatusModel.qml;
          "${d}/components/Sparkline.qml" = themedQmlFile variant ./components/Sparkline.qml;
          "${d}/components/StatusPanel.qml" = themedQmlFile variant ./components/StatusPanel.qml;
          "${d}/components/CalendarModel.qml" = themedQmlFile variant ./components/CalendarModel.qml;
          "${d}/components/PanelBeam.qml" = themedQmlFile variant ./components/PanelBeam.qml;
          "${d}/components/panel/PanelIcon.qml" = themedQmlFile variant ./components/panel/PanelIcon.qml;
          "${d}/components/panel/ToggleTile.qml" = themedQmlFile variant ./components/panel/ToggleTile.qml;
          "${d}/components/panel/ToggleGrid.qml" = themedQmlFile variant ./components/panel/ToggleGrid.qml;
          "${d}/components/panel/ToggleModel.qml" = themedQmlFile variant ./components/panel/ToggleModel.qml;
          "${d}/components/panel/ToggleTip.qml" = themedQmlFile variant ./components/panel/ToggleTip.qml;
          "${d}/components/panel/ClockWeatherHead.qml" = themedQmlFile variant ./components/panel/ClockWeatherHead.qml;
          "${d}/components/panel/WeatherModel.qml" = themedQmlFile variant ./components/panel/WeatherModel.qml;
          "${d}/components/panel/PanelNavButton.qml" = themedQmlFile variant ./components/panel/PanelNavButton.qml;
          "${d}/components/panel/CalendarPane.qml" = themedQmlFile variant ./components/panel/CalendarPane.qml;
          "${d}/components/panel/MetricsPane.qml" = themedQmlFile variant ./components/panel/MetricsPane.qml;
          "${d}/components/panel/MetricsModel.qml" = themedQmlFile variant ./components/panel/MetricsModel.qml;
          "${d}/components/panel/DiskPane.qml" = themedQmlFile variant ./components/panel/DiskPane.qml;
          "${d}/components/panel/DiskModel.qml" = themedQmlFile variant ./components/panel/DiskModel.qml;
          "${d}/components/panel/NotificationServer.qml" = themedQmlFile variant ./components/panel/NotificationServer.qml;
          "${d}/components/panel/NotificationRow.qml" = themedQmlFile variant ./components/panel/NotificationRow.qml;
          "${d}/components/panel/NotificationToasts.qml" = themedQmlFile variant ./components/panel/NotificationToasts.qml;
          "${d}/components/panel/NotificationPane.qml" = themedQmlFile variant ./components/panel/NotificationPane.qml;
          "${d}/components/panel/AudioModel.qml" = themedQmlFile variant ./components/panel/AudioModel.qml;
          "${d}/components/panel/AudioPane.qml" = themedQmlFile variant ./components/panel/AudioPane.qml;
          "${d}/components/panel/MobileModel.qml" = themedQmlFile variant ./components/panel/MobileModel.qml;
          "${d}/components/panel/MobilePane.qml" = themedQmlFile variant ./components/panel/MobilePane.qml;
          "${d}/components/panel/MobileAction.qml" = themedQmlFile variant ./components/panel/MobileAction.qml;
          "${d}/components/panel/messages/ContactsModel.qml" = themedQmlFile variant ./components/panel/messages/ContactsModel.qml;
          "${d}/components/panel/messages/MessageHue.qml" = themedQmlFile variant ./components/panel/messages/MessageHue.qml;
          "${d}/components/panel/messages/MessageStore.qml" = themedQmlFile variant ./components/panel/messages/MessageStore.qml;
          "${d}/components/panel/messages/MessageAvatar.qml" = themedQmlFile variant ./components/panel/messages/MessageAvatar.qml;
          "${d}/components/panel/messages/MessageTokens.qml" = themedQmlFile variant ./components/panel/messages/MessageTokens.qml;
          "${d}/components/panel/messages/ThreadList.qml" = themedQmlFile variant ./components/panel/messages/ThreadList.qml;
          "${d}/components/panel/messages/ConversationView.qml" = themedQmlFile variant ./components/panel/messages/ConversationView.qml;
          "${d}/components/panel/messages/MessagesModel.qml" = themedQmlFile variant ./components/panel/messages/MessagesModel.qml;
          "${d}/components/panel/messages/ComposeRow.qml" = themedQmlFile variant ./components/panel/messages/ComposeRow.qml;
          "${d}/components/PanelSheet.qml" = themedQmlFile variant ./components/PanelSheet.qml;
          "${d}/components/ControlPanel.qml" = themedQmlFile variant ./components/ControlPanel.qml;
        };
    in
    treeFor "dark" // treeFor "light";

  # `quickshell -c widgets` resolves through this symlink, which darkman
  # repoints on every sunrise/sunset. It must NOT be an xdg.configFile entry:
  # that would make it a read-only store symlink darkman could not replace.
  # Seeded to the dark tree; darkman corrects it on its next run.
  #
  # The link is made by modules/lib/quickshell-tree-link.nix rather than a bare
  # `ln -sfn`, because on the first application of this change widgets/ is
  # still a real directory and `ln -sfn` would link *into* it. See that file.
  # Only link when `widgets` is not already a symlink: darkman owns which tree
  # it points at, and relinking unconditionally would point a daytime desktop
  # at the dark tree and force a second quickshell restart on every switch.
  # The repair path still runs on first application, when it is a real
  # directory rather than a symlink.
  home.activation.quickshellThemeTree = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ ! -L "${config.xdg.configHome}/quickshell/widgets" ]; then
      run ${treeLink} "${config.xdg.configHome}/quickshell/widgets-dark" "${config.xdg.configHome}/quickshell/widgets"
    fi
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
