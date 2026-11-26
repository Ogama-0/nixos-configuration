import QtQuick
import Quickshell
import Quickshell.Wayland

// The name of the toggle you are hovering. Its own layer surface, not an
// item inside the panel, and that is not a style choice: the panel clips its
// children to the sheet's rounded corners, so a tip drawn inside it could
// never cross the top edge - which is exactly where the tip for a top-row
// tile has to go.
//
// Anchored to the panel's own surface so it tracks the tile without knowing
// anything about outputs.
PanelWindow {
    id: root

    property string label: ""
    property real anchorX: 0      // screen-relative centre of the tile
    property real anchorY: 0      // screen-relative top of the tile
    property real uiScale: 1

    visible: label !== ""

    anchors { top: true; left: true }
    margins.left: Math.round(anchorX - implicitWidth / 2)
    margins.top: Math.round(anchorY - implicitHeight - 7 * uiScale)

    implicitWidth: text.implicitWidth + 18 * uiScale
    implicitHeight: text.implicitHeight + 8 * uiScale

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "laser-bar-panel-tip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Never takes the pointer: it follows the cursor around and would
    // otherwise sit between the cursor and the tile it describes.
    mask: Region {}

    Rectangle {
        anchors.fill: parent
        radius: 7 * root.uiScale
        // The capsule pair, not the accent pair: capsuleFill/capsuleInk is
        // a light plate with dark ink in BOTH variants, which is what a
        // tooltip wants. @onAccentInk@ would be near-black on near-black in
        // light, because the light plate there is base05.
        color: "@capsuleFill@"

        Text {
            id: text
            anchors.centerIn: parent
            text: root.label
            color: "@capsuleInk@"
            font.pixelSize: Math.round(11 * root.uiScale)
            font.weight: Font.Medium
        }
    }
}
