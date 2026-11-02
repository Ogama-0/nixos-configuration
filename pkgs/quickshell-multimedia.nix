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
    rm $out/bin/quickshell
    makeWrapper ${quickshell}/bin/quickshell $out/bin/quickshell \
      --prefix QML_IMPORT_PATH : "${qt6.qtmultimedia}/lib/qt-6/qml" \
      --prefix QT_PLUGIN_PATH : "${qt6.qtmultimedia}/lib/qt-6/plugins"
  '';
}
