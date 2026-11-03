{ symlinkJoin, makeWrapper, quickshell, qt6 }:

# quickshell's QML import path is baked in at build time - qtdeclarative,
# qtwayland, qtbase - and does not include QtMultimedia. Importing it from a
# shell component fails the whole configuration, not the component (see
# docs/superpowers/specs/2026-11-02-messages-attachments-design.md). Both
# prefixes below are required, not redundant: QML_IMPORT_PATH alone makes
# `import QtMultimedia` succeed but leaves the media backend unreachable, so
# MediaPlayer construction fails with "Not available" - QT_PLUGIN_PATH is
# what lets Qt find the ffmpeg plugin that actually decodes anything.
symlinkJoin {
  name = "quickshell-multimedia";
  paths = [ quickshell ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    # `qs` is quickshell's own canonical short name for this same binary -
    # symlinkJoin carries it over from the unwrapped package, and it is on
    # PATH exactly like `quickshell` is. Leaving it as a symlink to the
    # unwrapped store path means `qs -c widgets` skips QML_IMPORT_PATH
    # entirely: `import QtMultimedia` fails and takes the whole config down
    # the same way the unwrapped `quickshell` did before this wrapper
    # existed. Both names need the same wrapper, not just the one a human
    # is more likely to type first.
    rm $out/bin/quickshell $out/bin/qs
    makeWrapper ${quickshell}/bin/quickshell $out/bin/quickshell \
      --prefix QML_IMPORT_PATH : "${qt6.qtmultimedia}/lib/qt-6/qml" \
      --prefix QT_PLUGIN_PATH : "${qt6.qtmultimedia}/lib/qt-6/plugins"
    makeWrapper ${quickshell}/bin/quickshell $out/bin/qs \
      --prefix QML_IMPORT_PATH : "${qt6.qtmultimedia}/lib/qt-6/qml" \
      --prefix QT_PLUGIN_PATH : "${qt6.qtmultimedia}/lib/qt-6/plugins"
  '';
}
