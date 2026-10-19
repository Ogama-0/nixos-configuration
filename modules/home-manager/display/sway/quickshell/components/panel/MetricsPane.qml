import QtQuick

// CPU, GPU and RAM as three bars with their numbers in Orbitron.
//
// A metric that is unavailable shows a dash rather than a zero. Zero is a
// claim about the hardware; a dash is the truth about the reading.
Item {
    id: root

    property real uiScale: 1
    property int cpuPct: -1
    property int gpuPct: -1
    property int ramPct: -1

    // Past this a bar turns amber. Not an alarm, just the point where it is
    // worth your eye.
    readonly property int warnAt: 70

    Column {
        anchors.fill: parent
        spacing: 10 * root.uiScale

        Repeater {
            model: [
                { label: "CPU", value: root.cpuPct },
                { label: "GPU", value: root.gpuPct },
                { label: "RAM", value: root.ramPct }
            ]

            Item {
                required property var modelData
                width: parent.width
                height: 19 * root.uiScale

                readonly property bool known: modelData.value >= 0

                Text {
                    id: label
                    width: 34 * root.uiScale
                    height: parent.height
                    text: modelData.label
                    color: "@mutedColor@"
                    font.pixelSize: Math.round(11.5 * root.uiScale)
                    font.weight: Font.Medium
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    id: track
                    x: label.width + 12 * root.uiScale
                    y: (parent.height - height) / 2
                    width: parent.width - x - 68 * root.uiScale
                    height: 5 * root.uiScale
                    radius: height / 2
                    color: "@plateBg@"

                    Rectangle {
                        width: parent.width
                            * Math.max(0, Math.min(100, modelData.value)) / 100
                        height: parent.height
                        radius: parent.radius
                        color: modelData.value >= root.warnAt
                            ? "@degradedColor@" : "@greenColor@"
                        visible: known
                    }
                }

                Text {
                    x: parent.width - width
                    height: parent.height
                    text: known ? modelData.value + "%" : "—"
                    color: "@clockColor@"
                    font.family: "Orbitron"
                    font.pixelSize: Math.round(17 * root.uiScale)
                    font.weight: Font.DemiBold
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
