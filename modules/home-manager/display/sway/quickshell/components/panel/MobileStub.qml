import QtQuick

// A placeholder, and it should look like one.
//
// The phone's name, battery and signal land here once there is a KDE Connect
// module to ask. Until then this says so rather than drawing a convincing
// empty device.
Item {
    id: root

    property real uiScale: 1

    opacity: 0.6

    Column {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 6 * root.uiScale

        Text {
            text: "Mobile"
            color: "@clockColor@"
            font.pixelSize: Math.round(13 * root.uiScale)
            font.weight: Font.DemiBold
        }

        Text {
            width: root.width
            text: "Phone name, battery and signal land here once the "
                + "KDE Connect module exists."
            color: "@mutedColor@"
            font.pixelSize: Math.round(12.5 * root.uiScale)
            wrapMode: Text.WordWrap
        }
    }
}
