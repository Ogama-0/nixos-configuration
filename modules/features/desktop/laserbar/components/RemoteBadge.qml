import QtQuick

// "This is coming out of the phone, not out of here."
//
// Drawn rather than fonted: the bar and the music card share no icon font,
// and two rectangles are cheaper than pulling one in for a single glyph.
Item {
    id: root

    property color tint: "#ffffff"
    property real glyphHeight: 11

    implicitHeight: root.glyphHeight
    implicitWidth: Math.round(root.glyphHeight * 0.58)

    readonly property real stroke: Math.max(1, Math.round(root.glyphHeight / 11))

    Rectangle {
        anchors.fill: parent
        radius: Math.max(1.5, parent.width * 0.24)
        color: "transparent"
        border.color: root.tint
        border.width: root.stroke
    }

    // The earpiece slot. Without it this is a rounded box, which at 11px
    // reads as nothing at all.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.17)
        width: Math.round(parent.width * 0.44)
        height: root.stroke
        radius: height / 2
        color: root.tint
    }
}
