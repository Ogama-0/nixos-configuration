import QtQuick
import "." as Components

// The centred time readout, on the shared BarShell chassis: a flared capsule
// the beam opens into, with the time in Orbitron and nothing else on it.
//
// Orbitron rather than the originally requested Corpta DEMO, which has no
// digit or colon glyphs at all and so can never render a clock. Orbitron is
// properly licensed, digit-complete, and installed system-wide via
// pkgs/orbitron-font.nix, so it is referenced by family name with no
// FontLoader or file-path trick.
Components.RevealMask {
    id: root

    property bool active: false

    // A dark tint of the rail covering this module, so the outline reads as
    // the beam continuing through it rather than as a black box laid on top.
    property color strokeColor: "@capsuleInk@"
    // Item-local x of the beams' meeting point when it lands inside this
    // module, or -1. See BarShell.
    property real seamX: -1
    property color wireColor: "@capsuleInk@"
    property color wireColorAfterSeam: "@capsuleInk@"

    // Read by BarSlots, which does the placing. See BarSlots.qml.
    property string slotSide: "centre"
    property int slotOrder: 0
    property bool slotWired: false

    // Includes both flares, via BarShell's own width: a module sized to its
    // body alone would have its flares revealed on a different schedule from
    // the capsule they belong to.
    width: shell.width
    height: shell.height

    // See RevealMask.qml: root.x is panel-local only when this is a direct
    // child of the panel content, which it is here (LaserBar.qml places it
    // straight under PanelWindow), so no originXOverride is needed.

    Components.BarShell {
        id: shell
        bodyWidth: 128
        bodyHeight: 38
        strokeColor: root.strokeColor
        seamX: root.seamX
        wireColor: root.wireColor
        wireColorAfterSeam: root.wireColorAfterSeam

        Text {
            id: clockText
            anchors.centerIn: parent
            color: "@capsuleInk@"
            font.family: "Orbitron"
            font.pixelSize: 19
            font.bold: true
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "HH:mm")
    }
}
