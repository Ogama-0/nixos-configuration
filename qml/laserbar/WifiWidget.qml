import QtQuick

// Network name and a four-bar strength readout.
//
// An earlier version also drove the right rail's wave amplitude from the
// strength, which made the two rails visibly different; that was dropped on
// purpose, so both sides share one wave equation and the strength is shown
// only here.
Item {
    id: root

    property int pos: 1
    property bool groupWired: false
    property bool active: false
    property real bodyHeight: 38
    property real uiScale: 1

    property string ssid: ""
    property real strength: 0
    property bool connected: false

    readonly property int bars: 4
    // A strength that arrives undefined or NaN - no device, or a backend that
    // never reported - must not reach the arithmetic below.
    readonly property real safeStrength:
        connected && !isNaN(strength) ? Math.max(0, Math.min(1, strength)) : 0
    // Ceil, not round: rounding leaves a connected network below 12% signal
    // showing zero lit bars, pixel-identical to being offline.
    readonly property int litBars:
        connected ? Math.max(1, Math.ceil(safeStrength * bars)) : 0

    implicitWidth: 148 * uiScale
    width: implicitWidth

    Text {
        // An empty capsule says nothing useful. Name the state instead.
        text: root.connected && root.ssid !== "" ? root.ssid : "offline"
        color: "@capsuleInk@"
        opacity: root.connected ? 1 : 0.55
        font.family: "Orbitron"
        font.pixelSize: Math.round(12 * root.uiScale)
        font.weight: Font.DemiBold
        elide: Text.ElideRight

        x: 12 * root.uiScale
        width: 78 * root.uiScale
        anchors.verticalCenter: parent.verticalCenter
    }

    Repeater {
        model: root.bars

        Rectangle {
            required property int index

            readonly property real barHeight: (6 + index * 4) * root.uiScale

            x: (100 + index * 9) * root.uiScale
            y: root.bodyHeight - 12 * root.uiScale - barHeight
            width: 5.2 * root.uiScale
            height: barHeight
            radius: 1.4 * root.uiScale
            color: "@capsuleInk@"
            opacity: index < root.litBars ? 0.9 : 0.2
        }
    }
}
