import QtQuick

// A clickable area on the bar, with the hover and press feedback every
// other one should have. This is how a widget becomes interactive:
//
//     BarButton {
//         width: 28 * root.uiScale
//         height: root.bodyHeight
//         onClicked: Dnd.toggle()
//
//         Text { anchors.centerIn: parent; text: "DND" }
//     }
//
// Children are its content, so it wraps whatever the widget already drew.
// Set `enabled: false` (Item's own property) for an action that is not
// available right now - the feedback goes with it and the click is not
// delivered, which is what a greyed-out control should do.
//
// The pointer only reaches the bar while it is revealed; see the input
// region in LaserBar.qml for how that is arranged and what it costs.
Item {
    id: root

    signal clicked

    // What the feedback plate is tinted with. A widget on a coloured rail
    // usually wants `railColor`; the default is the capsule's own ink.
    property color tint: "@capsuleInk@"
    property real plateRadius: Math.min(width, height) / 2

    readonly property alias hovered: area.containsMouse
    readonly property alias held: area.pressed

    default property alias content: holder.data

    // Behind the content, so a disc or a glyph sits on top of its own
    // highlight rather than under it.
    Rectangle {
        anchors.fill: parent
        radius: root.plateRadius
        color: root.tint
        opacity: !root.enabled ? 0 : area.pressed ? 0.26 : area.containsMouse ? 0.13 : 0

        // Short: this is a bar you hold a key to see, so feedback that
        // takes its time is feedback you never see.
        Behavior on opacity {
            NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
        }
    }

    Item {
        id: holder
        anchors.fill: parent
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
