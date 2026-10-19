import QtQuick
import ".."

// The notification centre, with the audio controls welded underneath it.
//
// `items` is a plain list so a fixture can feed it the ugly cases - no body,
// no app name, a body the size of a small file - without a notification bus
// being involved.
Item {
    id: root

    property real uiScale: 1
    property var items: []

    // Drawn at most; the rest exist in the model and are counted, not laid
    // out. A flood of two hundred must not become two hundred delegates.
    readonly property int maxRows: 6

    signal clearAllAsked
    signal dismissed(int index)

    default property alias footer: footerSlot.data

    Item {
        id: head
        width: parent.width
        height: 18 * root.uiScale

        Text {
            text: "Notifications"
            color: "@clockColor@"
            font.pixelSize: Math.round(13 * root.uiScale)
            font.weight: Font.DemiBold
        }

        Text {
            id: clearAll
            x: parent.width - width
            text: root.items.length === 0 ? "" : "Clear all"
            color: clearArea.containsMouse ? "@clockColor@" : "@mutedColor@"
            font.pixelSize: Math.round(11.5 * root.uiScale)

            MouseArea {
                id: clearArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.clearAllAsked()
            }
        }
    }

    Text {
        y: head.height + 12 * root.uiScale
        visible: root.items.length === 0
        text: "Nothing waiting."
        color: "@mutedColor@"
        font.pixelSize: Math.round(12.5 * root.uiScale)
    }

    Column {
        id: list
        y: head.height + 10 * root.uiScale
        width: parent.width
        spacing: 8 * root.uiScale

        Repeater {
            model: root.items.slice(0, root.maxRows)

            Rectangle {
                required property var modelData
                required property int index

                width: list.width
                height: 58 * root.uiScale
                radius: 12 * root.uiScale
                color: "@plateBg@"
                // So the accent edge below follows the rounded corners
                // instead of leaving a wedge of ground at each end of it.
                clip: true

                // Full height rather than inset: a stub floating beside the
                // text reads as debris, a full edge reads as a margin.
                Rectangle {
                    width: 2 * root.uiScale
                    height: parent.height
                    radius: width
                    color: "@greenColor@"
                }

                Column {
                    x: 13 * root.uiScale
                    y: 9 * root.uiScale
                    width: parent.width - 26 * root.uiScale
                    spacing: 3 * root.uiScale

                    Text {
                        width: parent.width
                        // An app that does not name itself still gets a row.
                        text: modelData.appName || "Unknown app"
                        color: "@mutedColor@"
                        font.pixelSize: Math.round(10 * root.uiScale)
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: modelData.summary || modelData.body || "(no title)"
                        color: "@clockColor@"
                        font.pixelSize: Math.round(12.5 * root.uiScale)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        // One line, elided. A body can be kilobytes long and
                        // must not be allowed to set this row's height.
                        text: modelData.summary ? (modelData.body || "") : ""
                        color: "@mutedColor@"
                        font.pixelSize: Math.round(12 * root.uiScale)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.dismissed(index)
                }
            }
        }

        Text {
            visible: root.items.length > root.maxRows
            text: "and " + (root.items.length - root.maxRows) + " more"
            color: "@mutedColor@"
            font.pixelSize: Math.round(11.5 * root.uiScale)
        }
    }

    // Audio lives below a beam at the bottom of this column.
    PanelBeam {
        horizontal: true
        width: root.width
        y: footerSlot.y - 12 * root.uiScale
        visible: footerSlot.children.length > 0
    }

    Item {
        id: footerSlot
        width: root.width
        height: childrenRect.height
        y: root.height - height
    }
}
