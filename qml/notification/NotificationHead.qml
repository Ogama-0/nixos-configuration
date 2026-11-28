import QtQuick
import Quickshell

// Who sent it, how many, and when - the line above a notification's text.
//
// All four in ONE row, in flow, left to right: icon, app name, count badge,
// relative time. The badge used to be pinned to the plate's top-right corner
// with the text column subtracting its width back out; adding a timestamp to
// that corner drew the count straight over it. Laying them out instead of
// stacking them is what stops the two colliding, and it lets the text column
// have the full width back.
Item {
    id: root

    property real uiScale: 1
    property string appName: ""
    property string appIcon: ""
    property string image: ""
    // 1 means no badge: a "1" on every single notification is noise.
    property int count: 1
    property string timeText: ""
    // Shown on a pack so it announces that it opens, rather than leaving you
    // to discover it. The toast flips this to "collapse" while open.
    property string hintText: ""

    implicitHeight: Math.max(icon.visible ? icon.height : 0,
                             label.implicitHeight,
                             badge.visible ? badge.height : 0)

    // Where the app name has to stop. Everything right of this is fixed
    // width and laid out right to left - time, then hint, then badge - so
    // the name takes whatever is left and elides into it.
    readonly property real textLimit:
        badge.visible ? badge.x : (hint.visible ? hint.x : stamp.x)

    readonly property string iconSource: {
        if (image) return Quickshell.iconPath(image, true);
        if (appIcon) return Quickshell.iconPath(appIcon, true);
        return "";
    }

    Image {
        id: icon
        visible: root.iconSource !== ""
        source: root.iconSource
        width: 15 * root.uiScale
        height: width
        anchors.verticalCenter: parent.verticalCenter
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
    }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        x: icon.visible ? icon.width + 7 * root.uiScale : 0
        width: Math.max(0, root.textLimit - 7 * root.uiScale - x)
        text: root.appName || "Unknown app"
        color: "@mutedColor@"
        font.pixelSize: Math.round(10 * root.uiScale)
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    Text {
        id: stamp
        anchors.verticalCenter: parent.verticalCenter
        x: parent.width - width
        text: root.timeText
        color: "@mutedColor@"
        font.pixelSize: Math.round(9.5 * root.uiScale)
        font.family: "Orbitron"
        elide: Text.ElideRight
    }

    Text {
        id: hint
        visible: root.hintText !== ""
        anchors.verticalCenter: parent.verticalCenter
        x: stamp.x - width - 8 * root.uiScale
        text: root.hintText
        color: "@mutedColor@"
        font.pixelSize: Math.round(9 * root.uiScale)
    }

    Rectangle {
        id: badge
        visible: root.count > 1
        anchors.verticalCenter: parent.verticalCenter
        x: (hint.visible ? hint.x : stamp.x) - width - 7 * root.uiScale
        width: countText.implicitWidth + 10 * root.uiScale
        height: countText.implicitHeight + 2 * root.uiScale
        radius: height / 2
        color: "@greenColor@"

        Text {
            id: countText
            anchors.centerIn: parent
            text: root.count
            color: "@onAccentInk@"
            font.pixelSize: Math.round(9.5 * root.uiScale)
            font.weight: Font.DemiBold
        }
    }
}
