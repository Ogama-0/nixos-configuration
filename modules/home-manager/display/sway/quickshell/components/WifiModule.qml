import QtQuick
import "." as Components

// Wi-Fi: the network's name and a four-bar strength readout.
//
// The strength is also carried by the beam itself - LaserBar.qml ramps the
// right rail's amplitude from this value at the screen edge down to a calm
// baseline past this capsule. That is done inside the one existing BeamSide,
// through its amplitudeAt hook, never by instantiating a second one for the
// varying stretch: two rails leave a visible seam where they meet and
// duplicate the blurred glow layer.
//
// Like the workspace strip, the values are properties and LaserBar.qml wires
// the live Quickshell.Networking source.
Components.RevealMask {
    id: root

    property string ssid: ""
    property real strength: 0
    property bool connected: false

    // Read by BarSlots, which does the placing. See BarSlots.qml.
    property string slotSide: "right"
    property int slotOrder: 0
    property bool slotWired: false
    property bool active: false

    readonly property int bars: 4
    // A strength that arrives undefined or NaN - no device, or a backend that
    // never reported - must not reach the arithmetic below.
    readonly property real safeStrength:
        connected && !isNaN(strength) ? Math.max(0, Math.min(1, strength)) : 0
    readonly property int litBars: Math.round(safeStrength * bars)

    width: shell.width
    height: shell.height

    Components.BarShell {
        id: shell
        bodyWidth: 148
        bodyHeight: 34

        Text {
            // An empty capsule says nothing useful. Name the state instead.
            text: root.connected && root.ssid !== "" ? root.ssid : "offline"
            color: "@capsuleInk@"
            opacity: root.connected ? 1 : 0.55
            font.family: "Orbitron"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight

            x: shell.bodyX + 12
            width: 78
            anchors.verticalCenter: parent.verticalCenter
        }

        Repeater {
            model: root.bars

            Rectangle {
                required property int index

                readonly property real barHeight: 6 + index * 4

                x: shell.bodyX + 100 + index * 9
                y: shell.inset + root.cellBaseline - barHeight
                width: 5.2
                height: barHeight
                radius: 1.4
                color: "@capsuleInk@"
                opacity: index < root.litBars ? 0.9 : 0.2
            }
        }
    }

    readonly property real cellBaseline: 26
}
