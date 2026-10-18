import QtQuick
import "." as Components

// The centred time readout.
//
// Orbitron rather than the originally requested Corpta DEMO, which has no
// digit or colon glyphs at all and so can never render a clock. Orbitron is
// properly licensed, digit-complete, and installed system-wide via
// pkgs/orbitron-font.nix, so it is referenced by family name with no
// FontLoader or file-path trick.
Components.BarModule {
    id: root

    slotSide: "centre"
    bodyWidth: 128

    Text {
        id: clockText
        anchors.centerIn: parent
        color: "@capsuleInk@"
        font.family: "Orbitron"
        font.pixelSize: 19
        font.bold: true
    }

    Timer {
        // Only while the bar is up. Running this for the whole session marks
        // the RevealMask's layer dirty once a second and re-renders its FBO
        // and mask, for a clock nobody is looking at.
        interval: 1000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "HH:mm")
    }
}
