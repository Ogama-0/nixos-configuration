import QtQuick

// One of the phone's two buttons. Icon plus word, because unlike the toggle
// grid these are actions you pick deliberately rather than glance at, and
// "clipboard" and "send file" are not guessable from a glyph.
Item {
    id: root

    property real uiScale: 1
    property string icon: ""
    property string label: ""

    signal activated

    height: 26 * uiScale

    Rectangle {
        anchors.fill: parent
        radius: 9 * root.uiScale
        color: area.pressed ? "@glassBorder@"
             : area.containsMouse ? "@plateBg@" : "transparent"
        border.width: 1
        border.color: "@glassBorder@"
        Behavior on color { ColorAnimation { duration: 90 } }
    }

    Row {
        anchors.centerIn: parent
        spacing: 6 * root.uiScale

        PanelIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            uiScale: root.uiScale * 0.6
            color: area.containsMouse ? "@clockColor@" : "@mutedColor@"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: area.containsMouse ? "@clockColor@" : "@mutedColor@"
            font.pixelSize: Math.round(11 * root.uiScale)
            font.weight: Font.Medium
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.activated()
    }
}
