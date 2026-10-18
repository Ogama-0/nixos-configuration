import QtQuick
import "." as Components

// Wi-Fi: the network's name and a four-bar strength readout.
//
// The values are properties and LaserBar.qml wires the live
// Quickshell.Networking source. An earlier version also drove the right
// rail's wave amplitude from the strength, which made the two rails visibly
// different; that was dropped on purpose, so both sides share one wave
// equation and the strength is shown only here.
Components.BarModule {
    id: root

    slotSide: "right"
    bodyWidth: 148

    property string ssid: ""
    property real strength: 0
    property bool connected: false

    readonly property int bars: 4
    // A strength that arrives undefined or NaN - no device, or a backend that
    // never reported - must not reach the arithmetic below.
    readonly property real safeStrength:
        connected && !isNaN(strength) ? Math.max(0, Math.min(1, strength)) : 0
    // Ceil, not round: rounding leaves a connected network below 12% signal
    // showing zero lit bars, which is pixel-identical to being offline.
    readonly property int litBars: connected ? Math.max(1, Math.ceil(safeStrength * bars)) : 0

    readonly property real barBaseline: 26

    Text {
        // An empty capsule says nothing useful. Name the state instead.
        text: root.connected && root.ssid !== "" ? root.ssid : "offline"
        color: "@capsuleInk@"
        opacity: root.connected ? 1 : 0.55
        font.family: "Orbitron"
        font.pixelSize: 12
        font.weight: Font.DemiBold
        elide: Text.ElideRight

        x: root.shell.bodyX + 12
        width: 78
        anchors.verticalCenter: parent.verticalCenter
    }

    Repeater {
        model: root.bars

        Rectangle {
            required property int index

            readonly property real barHeight: 6 + index * 4

            x: root.shell.bodyX + 100 + index * 9
            y: root.shell.bodyY + root.barBaseline - barHeight
            width: 5.2
            height: barHeight
            radius: 1.4
            color: "@capsuleInk@"
            opacity: index < root.litBars ? 0.9 : 0.2
        }
    }
}
