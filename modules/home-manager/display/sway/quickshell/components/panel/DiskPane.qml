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

    // A bar is a bar, not a slab. Dividing the column by the number of
    // mounts means one mount gets the whole 106px width and reads as a
    // filled panel rather than a meter, so the width is capped and the
    // group centred in whatever is left.
    readonly property real maxBarWidth: 26
    readonly property real barWidth: Math.min(
        maxBarWidth * uiScale,
        disks.length > 0
            ? (width - (disks.length - 1) * gap * uiScale) / disks.length
            : width)
    readonly property real groupWidth:
        disks.length * barWidth + Math.max(0, disks.length - 1) * gap * uiScale
    readonly property real groupX: (width - groupWidth) / 2

    Item {
        id: bars
        x: 0
        // Capped and sat at the bottom of the column. The zone is over 600
        // tall now and a bar that filled it would be a 450px slab reporting
        // one number; past a point more pixels stop meaning more precision.
        y: parent.height - 30 * root.uiScale - height
        width: parent.width
        height: Math.min(340 * root.uiScale,
                         parent.height - 30 * root.uiScale)

        Repeater {
            model: root.disks

            Rectangle {
                required property var modelData
                required property int index

                x: root.groupX + index * (root.barWidth + root.gap * root.uiScale)
                width: root.barWidth
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
        x: root.groupX
        y: bars.y + bars.height + 7 * root.uiScale
        width: root.groupWidth
        spacing: root.gap * root.uiScale

        Repeater {
            model: root.disks
            Text {
                required property var modelData
                width: root.barWidth
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
