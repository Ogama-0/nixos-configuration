import QtQuick

// The phone, when there is one: what it is, how much of it is left, and the
// two things worth doing from here without reaching for the GUI.
//
// When nothing is paired or reachable it says that plainly instead of
// drawing an empty device - a greyed-out battery and a blank name read as
// "broken", not as "no phone".
Item {
    id: root

    property real uiScale: 1
    property var device: null
    property bool connected: false

    signal guiAsked
    signal clipboardAsked
    signal fileAsked
    // Unlike the other three this one opens nothing and dismisses nothing -
    // it expands the panel into Messages, so the panel must stay up.
    signal messagesAsked

    // Drawn only when a device has been paired at all. With one paired but
    // out of reach the button is there and disabled, same as the compose
    // field: a control that disappears looks like a broken panel.
    property bool everPaired: connected

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
            uiScale: root.uiScale * 0.85
            color: "@greenColor@"
            y: 0
        }

        Text {
            x: phoneIcon.width + 8 * root.uiScale
            width: parent.width - x - signalGroup.width - 8 * root.uiScale
            height: phoneIcon.height
            text: root.device ? root.device.name : ""
            color: "@clockColor@"
            font.pixelSize: Math.round(13 * root.uiScale)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        // Network type and bars, right-aligned on the name's line. Hidden
        // whole rather than drawn empty when the phone has no connectivity
        // plugin - four grey bars is a claim about signal, not an absence.
        Row {
            id: signalGroup
            visible: root.device && root.device.signal >= 0
            x: parent.width - width
            height: phoneIcon.height
            spacing: 5 * root.uiScale

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.device ? root.device.network : ""
                color: "@mutedColor@"
                font.pixelSize: Math.round(10.5 * root.uiScale)
                font.weight: Font.Medium
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * root.uiScale
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        width: 3 * root.uiScale
                        height: (4 + index * 2.5) * root.uiScale
                        y: parent.height - height
                        radius: 1
                        color: root.device && root.device.signal > index
                            ? "@greenColor@" : "@plateBg@"
                    }
                }
            }
        }

        // Battery. A phone whose battery plugin is off is still a phone.
        Item {
            id: battery
            visible: root.device && root.device.charge >= 0
            y: phoneIcon.height + 9 * root.uiScale
            width: parent.width
            height: 26 * root.uiScale

            Text {
                id: charge
                text: root.device
                    ? root.device.charge + "%"
                      + (root.device.charging ? " · charging" : "")
                    : ""
                color: "@mutedColor@"
                font.pixelSize: Math.round(11.5 * root.uiScale)
            }

            Rectangle {
                y: charge.height + 5 * root.uiScale
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

        // ---- the actions ----
        //
        // Messages gets its own full-width row above the other two. It is the
        // one you reach for, the other two are occasional, and a third of a
        // 262px zone is not enough for a word plus a glyph.

        MobileAction {
            id: messagesButton
            y: battery.visible
                ? battery.y + battery.height + 10 * root.uiScale
                : phoneIcon.height + 12 * root.uiScale
            width: parent.width
            uiScale: root.uiScale
            icon: "bell"
            label: "Messages"
            // Enabled whenever a phone is PAIRED, not only when it is
            // reachable: everything already downloaded is still worth
            // reading, and sending is refused further in rather than by
            // making the door unopenable.
            opacity: root.everPaired ? 1 : 0.45
            onActivated: if (root.everPaired) root.messagesAsked()
        }

        Row {
            id: actions
            y: messagesButton.y + messagesButton.height + 7 * root.uiScale
            width: parent.width
            spacing: 7 * root.uiScale

            MobileAction {
                width: (actions.width - 7 * root.uiScale) / 2
                uiScale: root.uiScale
                icon: "clipboard"
                label: "Clipboard"
                onActivated: root.clipboardAsked()
            }
            MobileAction {
                width: (actions.width - 7 * root.uiScale) / 2
                uiScale: root.uiScale
                icon: "upload"
                label: "Send file"
                onActivated: root.fileAsked()
            }
        }

        Text {
            id: openLink
            y: parent.height - height
            text: "Open KDE Connect"
            color: openArea.containsMouse ? "@clockColor@" : "@mutedColor@"
            font.pixelSize: Math.round(11.5 * root.uiScale)

            // Only this line opens the GUI. A zone-wide click target would
            // sit under the two buttons and fire whenever one was missed.
            MouseArea {
                id: openArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.guiAsked()
            }
        }
    }
}
