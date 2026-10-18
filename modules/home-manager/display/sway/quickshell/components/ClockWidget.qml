import QtQuick

// The time. A widget: it sizes itself and knows nothing about the capsule,
// the beam or the reveal - BarGroup places it and BarSlots colours the
// capsule around it.
//
// Orbitron rather than the originally requested Corpta DEMO, which has no
// digit or colon glyphs at all and so can never render a clock. Orbitron is
// properly licensed, digit-complete, and installed system-wide via
// pkgs/orbitron-font.nix.
Item {
    id: root

    // Read by BarGroup: where this sits inside its group.
    property int pos: 1
    property bool groupWired: false
    // Bound by BarGroup.
    property bool active: false
    property real bodyHeight: 38

    implicitWidth: 128
    width: implicitWidth

    Text {
        id: clockText
        anchors.centerIn: parent
        color: "@capsuleInk@"
        font.family: "Orbitron"
        font.pixelSize: 19
        font.bold: true
    }

    Timer {
        // Only while the bar is up. Running this all session marks the
        // RevealMask's layer dirty once a second and re-renders its FBO and
        // mask, for a clock nobody is looking at.
        interval: 1000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "HH:mm")
    }
}
