import QtQuick

// Output device and volume, at the foot of the notification column.
Item {
    id: root

    property real uiScale: 1
    property var sinks: []
    property string deviceName: ""
    property int volumePct: 0
    property bool muted: false

    signal volumeAsked(int pct)
    signal muteAsked
    signal cycleAsked

    implicitHeight: 42 * uiScale

    Item {
        id: deviceRow
        width: parent.width
        height: 20 * root.uiScale

        PanelIcon {
            id: icon
            name: root.muted ? "speaker-muted" : "speaker"
            uiScale: root.uiScale * 0.75
            color: root.muted ? "@mutedColor@" : "@clockColor@"
            y: (parent.height - height) / 2

            MouseArea {
                anchors.fill: parent
                onClicked: root.muteAsked()
            }
        }

        Text {
            x: icon.width + 9 * root.uiScale
            width: parent.width - x
            height: parent.height
            // The name of the device, not its PipeWire node path: people
            // pick "Sennheiser HD 560S", not alsa_output.pci-0000_00.
            text: root.deviceName
            color: "@clockColor@"
            font.pixelSize: Math.round(12 * root.uiScale)
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter

            MouseArea {
                anchors.fill: parent
                // One output is not a choice; more than one and a click
                // moves to the next.
                enabled: root.sinks.length > 1
                onClicked: root.cycleAsked()
            }
        }
    }

    Rectangle {
        id: slider
        y: deviceRow.height + 12 * root.uiScale
        width: parent.width
        height: 5 * root.uiScale
        radius: height / 2
        color: "@plateBg@"

        Rectangle {
            width: parent.width * Math.max(0, Math.min(100, root.volumePct)) / 100
            height: parent.height
            radius: parent.radius
            color: root.muted ? "@mutedColor@" : "@greenColor@"
        }

        MouseArea {
            anchors.fill: parent
            // Generous vertical margin: a 5px target is not a control.
            anchors.topMargin: -10 * root.uiScale
            anchors.bottomMargin: -10 * root.uiScale
            onPressed: mouse => root.volumeAsked(Math.round(100 * mouse.x / width))
            onPositionChanged: mouse => root.volumeAsked(Math.round(100 * mouse.x / width))
        }
    }
}
