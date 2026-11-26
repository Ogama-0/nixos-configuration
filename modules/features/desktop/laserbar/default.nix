{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { config, lib, ... }:
    {
      options.ogama.desktop.laserbar.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.ogama.desktop.sway.enable;
        defaultText = lib.literalExpression "config.ogama.desktop.sway.enable";
        description = "the sway laser bar, its panels and widgets";
      };
    };
in
{
  flake.featureModules.nixos.laserbar = sharedOptions;

  flake.featureModules.home.laserbar =
    {
      pkgs,
      upkgs,
      lpkgs,
      config,
      lib,
      ...
    }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.desktop.laserbar.enable (
        let
          allColors = import ../../../../lib/theme-colors.nix;

          # Semantic status colours, per variant. They are NOT one base16 slot: the
          # two palettes disagree about where each hue lives, and several light slots
          # fail their contrast floors outright. The measured values live in
          # lib/palette.nix under `<mode>.status` - edit them there.
          #
          # The alpha prefixes are applied here because QML wants #AARRGGBB: FF for
          # the opaque bands, CC for the muted light column (base05 at 80%).
          palette = import ../../../../lib/palette.nix;

          statusColorsFor =
            variant:
            let
              st = palette.${variant}.status;
              opaque = c: "#FF" + builtins.substring 1 6 c;
            in
            {
              upColor = opaque st.up;
              degradedColor = opaque st.degraded;
              downColor = opaque st.down;
              mutedColor =
                if variant == "light" then "#CC" + builtins.substring 1 6 st.muted else opaque st.muted;
            };

          # The capsule is a light plate with a near-black outline in both variants,
          # which means reading from opposite ends of the palette depending on polarity
          # rather than from one fixed slot.
          capsuleColorsFor =
            variant:
            let
              c = allColors.${variant};
            in
            if variant == "light" then
              {
                capsuleFill = "#F2${c.base00}";
                capsuleInk = "#FF${c.base05}";
              }
            else
              {
                capsuleFill = "#F2${c.base05}";
                capsuleInk = "#FF${c.base00}";
              };

          # Messages' identity-hue pool: one accent slot per contact, hashed from the
          # phone number so a person keeps one colour forever.
          #
          # Not the same slots in both variants. Horizon light's base0A is #FBE0D9 -
          # near-white - and initials painted in it disappear into the cream sheet, so
          # light gets seven slots and dark gets eight. Dropping it from both instead
          # would cost dark a perfectly good yellow for a problem it does not have.
          msgHuesFor =
            variant:
            let
              c = allColors.${variant};
              opaque = v: "#FF" + v;
              slots =
                if variant == "light" then
                  [
                    c.base08
                    c.base09
                    c.base0B
                    c.base0C
                    c.base0D
                    c.base0E
                    c.base0F
                  ]
                else
                  [
                    c.base08
                    c.base09
                    c.base0A
                    c.base0B
                    c.base0C
                    c.base0D
                    c.base0E
                    c.base0F
                  ];
            in
            {
              msgHues = builtins.concatStringsSep "," (map opaque slots);
            };

          # The outgoing bubble, and the ink on it. base0D is the slot the bar already
          # treats as THE UI accent; base0B (@greenColor@) is this panel's "a thing is
          # on" colour and would make every message you sent read as a status light.
          #
          # In light that lands on #DA103F, a crimson rather than a blue. That is
          # Horizon light, not a mistake - the palette is not a recolour of the dark
          # set and no single slot means "blue" in both.
          msgAccentFor =
            variant:
            let
              c = allColors.${variant};
            in
            {
              msgAccent = "#FF" + c.base0D;
              msgAccentInk = if variant == "light" then "#FF" + c.base07 else "#FF" + c.base00;
            };

          # Ink on an accent (base0B) fill: base00 in dark, base07 in light. Light's
          # base00 is the cream ground, so an icon in it would vanish into the green.
          onAccentInkFor =
            variant:
            let
              c = allColors.${variant};
            in
            if variant == "light" then "#FF${c.base07}" else "#FF${c.base00}";

          # Built from the profile so the tailnet hostnames are never hardcoded in QML.
          #
          # `config.ogama.server.domain`, one level, from either side. host/profiles.nix builds
          # every profile as `base // (extra base)`; cfg-perso's extra sets
          # `server = cfg-server`, and cfg-server's own base already carries `domain`,
          # so `config.ogama.server.domain` is "ogama.me" from the personal profile and
          # `config.ogama.server.domain` is the same string from the server one.
          #
          # This said `.server.server` for a while, with a comment arguing the doubling
          # was deliberate. It is not: cfg-perso.server has no `server` attribute at
          # all (check with `nix eval --impure --expr 'builtins.attrNames (import
          # ./host/profiles.nix).cfg-perso.server'`), so that form simply threw.
          serverDomain = config.ogama.server.domain;

          statusApiUrl = "http://status.tail.${serverDomain}/api/v1/endpoints/statuses";
          metricsApiUrl = "http://metrics.tail.${serverDomain}/api/v1/query";

          # Lockscreen theming reuses the same @token@ substitution and the same
          # `allColors` palette as the bar; what differs is that each variant renders
          # its own component and artwork (see lockFor below).
          qmlTheme = import ../../../../lib/qml-theme.nix;

          treeLink = import ../../../../lib/quickshell-tree-link.nix { inherit pkgs; };

          systemctlBin = "${pkgs.systemd}/bin/systemctl";
          # The session's own sway, not pkgs.sway, so this pulls nothing extra into
          # the closure. See lib/swayfx.nix.
          swaymsgBin = "${import ../../../../lib/swayfx.nix pkgs}/bin/swaymsg";
          corptaFontPath = "${config.home.homeDirectory}/nixos-configuration/assets/fonts/Corpta-DEMO.otf";

          themeFor =
            variant:
            qmlTheme (
              {
                colors = allColors.${variant};
                laserColor = if variant == "light" then "#FFFFFF" else "#000000";
                wallpaperDirs = "${variant} both";
                inherit
                  systemctlBin
                  swaymsgBin
                  corptaFontPath
                  statusApiUrl
                  metricsApiUrl
                  ;
                # The control panel's idle tile writes this file and sway-idle.nix
                # guards every timeout command on its absence. Read off the
                # option rather than spelled here, so the two sides cannot
                # drift - an absent flag file reads as "idle management is on",
                # so a rename would fail silently in the permissive direction.
                idleInhibitFlag = config.ogama.desktop.swayIdle.inhibitFlagName;
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
                sheetBg =
                  if variant == "light" then "#F2${allColors.light.base00}" else "#EF${allColors.dark.base00}";
              }
              // statusColorsFor variant
              // capsuleColorsFor variant
              // msgHuesFor variant
              // msgAccentFor variant
            );

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
            lpkgs.quickshell-multimedia
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

              # The repo-root QML tree, shared with the greeter (which installs its
              # own corner of it from modules/features/desktop/greeter.nix).
              qmlRoot = ../../../../qml;
              qmlRootStr = toString qmlRoot + "/";
              qmlRel = p: lib.removePrefix qmlRootStr (toString p);

              # Walked, not enumerated. Every .qml under qml/ lands in both themed
              # trees at the same relative path, so adding a component is adding a
              # file. The hand-written list this replaces had to be edited twice for
              # every new file, and a forgotten entry failed at runtime as "X is not
              # a type" with a perfectly green `nix flake check`.
              #
              # Two exclusions, both load-bearing:
              #
              #   - greeter/ is installed into /etc/greeter by the NixOS module,
              #     because the greetd user cannot read /home. It shares the palette
              #     with this tree and nothing else.
              #   - lockscreen/Lock{Dark,Light}.qml are two deliberately different
              #     designs behind ONE installed Lock.qml - shell.qml instantiates
              #     `Lock`, and which design that is comes from the variant. Letting
              #     the walk install them under their own names would put the dark
              #     lockscreen in the light tree.
              installable =
                p:
                let
                  rel = qmlRel p;
                in
                lib.hasSuffix ".qml" rel
                && !(lib.hasPrefix "greeter/" rel)
                && !(builtins.elem rel [
                  "lockscreen/LockDark.qml"
                  "lockscreen/LockLight.qml"
                ]);

              qmlFiles = lib.filter installable (lib.filesystem.listFilesRecursive qmlRoot);

              # Each variant gets its own lockscreen artwork: dark uses the Arcane/Jinx
              # piece (see LockDark.qml), light keeps the original Nausicaa/snow
              # treatment (see LockLight.qml) - they are deliberately different
              # designs, not the same skin recoloured.
              lockFor = {
                dark =
                  lockVariant "dark" (qmlRoot + "/lockscreen/LockDark.qml")
                    "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/dark-lockscreen-arcane-jinx.jpeg";
                light = lockVariant "light" (
                  qmlRoot + "/lockscreen/LockLight.qml"
                ) "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png";
              };

              treeFor =
                variant:
                let
                  d = "quickshell/widgets-${variant}";
                in
                {
                  # Music.qml and MusicWidget.qml resolve cava as
                  # Quickshell.shellDir + "/cava.conf", so each tree needs its own
                  # copy; shellDir makes that automatic.
                  "${d}/cava.conf".text = cavaConf;
                  "${d}/lockscreen/Lock.qml" = lockFor.${variant};
                }
                // lib.listToAttrs (
                  map (p: lib.nameValuePair "${d}/${qmlRel p}" (themedQmlFile variant p)) qmlFiles
                );
            in
            treeFor "dark" // treeFor "light";

          # `quickshell -c widgets` resolves through this symlink, which darkman
          # repoints on every sunrise/sunset. It must NOT be an xdg.configFile entry:
          # that would make it a read-only store symlink darkman could not replace.
          # Seeded to the dark tree; darkman corrects it on its next run.
          #
          # The link is made by lib/quickshell-tree-link.nix rather than a bare
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
              ExecStart = "${lpkgs.quickshell-multimedia}/bin/quickshell -c widgets";
              Restart = "on-failure";
            };
            Install = {
              WantedBy = [ "graphical-session.target" ];
            };
          };
        }
      );
    };
}
