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
  } // statusColorsFor variant // capsuleColorsFor variant);

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
          "${d}/components/Calendar.qml" = themedQmlFile variant ./components/Calendar.qml;
          "${d}/components/RevealMask.qml" = themedQmlFile variant ./components/RevealMask.qml;
          "${d}/components/GlassPill.qml" = themedQmlFile variant ./components/GlassPill.qml;
          "${d}/components/ColorUtils.qml" = themedQmlFile variant ./components/ColorUtils.qml;
          "${d}/components/BarShell.qml" = themedQmlFile variant ./components/BarShell.qml;
          "${d}/components/BarModule.qml" = themedQmlFile variant ./components/BarModule.qml;
          "${d}/components/BarSlots.qml" = themedQmlFile variant ./components/BarSlots.qml;
          "${d}/components/WorkspaceIcon.qml" = themedQmlFile variant ./components/WorkspaceIcon.qml;
          "${d}/components/WorkspaceModule.qml" = themedQmlFile variant ./components/WorkspaceModule.qml;
          "${d}/components/WifiModule.qml" = themedQmlFile variant ./components/WifiModule.qml;
          "${d}/components/BeamSide.qml" = themedQmlFile variant ./components/BeamSide.qml;
          "${d}/components/CollisionEffects.qml" = themedQmlFile variant ./components/CollisionEffects.qml;
          "${d}/components/ClockModule.qml" = themedQmlFile variant ./components/ClockModule.qml;
          "${d}/components/LaserBar.qml" = themedQmlFile variant ./components/LaserBar.qml;
          "${d}/components/StatusModel.qml" = themedQmlFile variant ./components/StatusModel.qml;
          "${d}/components/Sparkline.qml" = themedQmlFile variant ./components/Sparkline.qml;
          "${d}/components/StatusPanel.qml" = themedQmlFile variant ./components/StatusPanel.qml;
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
