import QtQuick

// Disk usage as vertical bars, one per mount, with the free total under it.
//
// Vertical because the column is 106 wide and 531 tall: a horizontal meter
// per disk would be 70px of track, which is not a meter, it is a hint.
Item {
    id: root

    property real uiScale: 1
    // [{ label, usedFraction }]
    property var disks: []
    property string freeTotal: ""

    readonly property int warnAt: 85
    readonly property real gap: 9

    Item {
        id: bars
        x: 0
        y: 0
        width: parent.width
        height: parent.height - 30 * root.uiScale

        Repeater {
            model: root.disks

            Rectangle {
                required property var modelData
                required property int index

                readonly property real cell:
                    (bars.width - (root.disks.length - 1) * root.gap * root.uiScale)
                    / root.disks.length

                x: index * (cell + root.gap * root.uiScale)
                width: cell
                height: bars.height
                radius: 6 * root.uiScale
                color: "@plateBg@"
                clip: true

                Rectangle {
                    width: parent.width
                    height: parent.height * Math.max(0, Math.min(1, modelData.usedFraction))
                    y: parent.height - height
                    radius: parent.radius
                    color: modelData.usedFraction * 100 >= root.warnAt
                        ? "@degradedColor@" : "@greenColor@"
                }
            }
        }
    }

    Row {
        id: labels
        y: bars.height + 7 * root.uiScale
        width: parent.width
        spacing: root.gap * root.uiScale

        Repeater {
            model: root.disks
            Text {
                required property var modelData
                width: (labels.width - (root.disks.length - 1) * root.gap * root.uiScale)
                       / root.disks.length
                text: modelData.label
                color: "@mutedColor@"
                font.pixelSize: Math.round(10 * root.uiScale)
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }

    Text {
        y: labels.y + 14 * root.uiScale
        width: parent.width
        text: root.freeTotal
        color: "@mutedColor@"
        font.pixelSize: Math.round(10.5 * root.uiScale)
        horizontalAlignment: Text.AlignHCenter
    }
}
