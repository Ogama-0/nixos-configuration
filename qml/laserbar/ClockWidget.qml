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

    // Clicking the clock summons the control panel. The widget does not know
    // what a panel is: it says the clock was clicked and LaserBar passes that
    // up to shell.qml, which owns both.
    signal panelRequested

    // Read by BarGroup: where this sits inside its group.
    property int pos: 1
    property bool groupWired: false
    // Bound by BarGroup.
    property bool active: false
    property real bodyHeight: 38
    property real uiScale: 1

    implicitWidth: 128 * uiScale
    width: implicitWidth

    // Three pieces rather than one string, so the gap either side of the
    // colon is exact. Orbitron sets HH:MM tight, and a thin-space character
    // would depend on the font actually having one.
    Row {
        anchors.centerIn: parent
        spacing: 2 * root.uiScale

        Text {
            id: hoursText
            color: "@capsuleInk@"
            font.family: "Orbitron"
            font.pixelSize: Math.round(19 * root.uiScale)
            font.bold: true
        }
        Text {
            text: ":"
            color: "@capsuleInk@"
            font.family: "Orbitron"
            font.pixelSize: Math.round(19 * root.uiScale)
            font.bold: true
        }
        Text {
            id: minutesText
            color: "@capsuleInk@"
            font.family: "Orbitron"
            font.pixelSize: Math.round(19 * root.uiScale)
            font.bold: true
        }
    }

    // Covers the whole widget, under nothing: the capsule is the target, not
    // the glyphs. The pointer only reaches the bar while it is revealed; see
    // the input region in LaserBar.qml.
    BarButton {
        anchors.fill: parent
        onClicked: root.panelRequested()
    }

    Timer {
        // Only while the bar is up. Running this all session marks the
        // RevealMask's layer dirty once a second and re-renders its FBO and
        // mask, for a clock nobody is looking at.
        interval: 1000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date();
            hoursText.text = Qt.formatDateTime(now, "HH");
            minutesText.text = Qt.formatDateTime(now, "mm");
        }
    }
}
