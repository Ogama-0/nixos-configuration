import QtQuick

// The phone, when there is one. Clicking anywhere in the zone opens the KDE
// Connect GUI, which is where everything this zone does not show lives.
//
// When nothing is paired or reachable it says that plainly instead of
// drawing an empty device - a greyed-out battery and a blank name read as
// "broken", not as "no phone".
Item {
    id: root

    property real uiScale: 1
    property var device: null
    property bool connected: false

    signal activated

    readonly property int lowAt: 20

    // ---- nothing connected ----

    Column {
        visible: !root.connected
        width: parent.width
        spacing: 6 * root.uiScale
        opacity: 0.6

        Text {
            text: "Mobile"
            color: "@clockColor@"
            font.pixelSize: Math.round(13 * root.uiScale)
            font.weight: Font.DemiBold
        }
        Text {
            width: root.width
            text: "No phone connected. Pair one in KDE Connect."
            color: "@mutedColor@"
            font.pixelSize: Math.round(12.5 * root.uiScale)
            wrapMode: Text.WordWrap
        }
    }

    // ---- a phone ----

    Item {
        visible: root.connected
        anchors.fill: parent

        PanelIcon {
            id: phoneIcon
            name: "phone"
            uiScale: root.uiScale
            color: "@greenColor@"
            y: 0
        }

        Text {
            id: phoneName
            x: phoneIcon.width + 10 * root.uiScale
            width: parent.width - x
            height: phoneIcon.height
            text: root.device ? root.device.name : ""
            color: "@clockColor@"
            font.pixelSize: Math.round(13 * root.uiScale)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        // Battery, when the device reports one. A phone whose battery
        // plugin is off is still a connected phone.
        Item {
            id: battery
            visible: root.device && root.device.charge >= 0
            y: phoneIcon.height + 12 * root.uiScale
            width: parent.width
            height: 16 * root.uiScale

            Text {
                id: charge
                text: root.device
                    ? root.device.charge + "%"
                      + (root.device.charging ? " · charging" : "")
                    : ""
                color: "@mutedColor@"
                font.pixelSize: Math.round(12 * root.uiScale)
            }

            Rectangle {
                y: charge.height + 6 * root.uiScale
                width: parent.width
                height: 5 * root.uiScale
                radius: height / 2
                color: "@plateBg@"

                Rectangle {
                    width: parent.width
                        * Math.max(0, Math.min(100,
                            root.device ? root.device.charge : 0)) / 100
                    height: parent.height
                    radius: parent.radius
                    color: root.device && root.device.charge <= root.lowAt
                        && !root.device.charging
                        ? "@degradedColor@" : "@greenColor@"
                }
            }
        }

        Text {
            y: parent.height - height
            text: "Open KDE Connect"
            color: area.containsMouse ? "@clockColor@" : "@mutedColor@"
            font.pixelSize: Math.round(11.5 * root.uiScale)
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.connected
        onClicked: root.activated()
    }
}
