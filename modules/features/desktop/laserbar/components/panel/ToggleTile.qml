import QtQuick

// One toggle. An icon and nothing else - the name lives in the tooltip
// (ToggleTip.qml), which is the only place a toggle spells itself out.
//
// Three appearances, and the difference between them is information:
//
//   active  accent fill, ink-on-accent icon. State must NOT be carried by
//           icon colour alone: base0B in light is #94E1B0, which is not
//           legible as a thin stroke on the cream sheet.
//   resting faint plate, muted icon.
//   action  no fill at all, outlined. Lock is not a state you are in, it is
//           a thing you do, and it should not look like the rest.
Item {
    id: root

    property string iconName: ""
    property string label: ""
    property bool active: false
    property bool isAction: false
    property real uiScale: 1

    signal activated
    signal hoverEntered(bool entered)

    Rectangle {
        anchors.fill: parent
        radius: 14 * root.uiScale
        color: root.isAction
            ? "transparent"
            : root.active ? "@greenColor@" : "@plateBg@"
        border.width: root.isAction ? 1 : 0
        border.color: "@glassBorder@"

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "@plateBg@"
            opacity: area.pressed ? 1.0 : area.containsMouse ? 0.6 : 0
            // Short, because this is a panel you summon and dismiss in a
            // couple of seconds: feedback that takes its time is feedback
            // you never see.
            Behavior on opacity { NumberAnimation { duration: 90 } }
        }
    }

    PanelIcon {
        anchors.centerIn: parent
        name: root.iconName
        uiScale: root.uiScale
        color: root.active && !root.isAction ? "@onAccentInk@" : "@mutedColor@"
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.activated()
        onEntered: root.hoverEntered(true)
        onExited: root.hoverEntered(false)
    }
}
