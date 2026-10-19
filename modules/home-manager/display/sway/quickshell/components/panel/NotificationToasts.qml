import QtQuick
import Quickshell
import Quickshell.Wayland

// What a notification looks like when it arrives, as opposed to when you go
// looking for it. Same plate, same accent edge, same NotificationRow as the
// centre - a toast that looks different from its own entry in the list is
// two designs for one thing.
//
// Its own layer surface, top right, taking the pointer only where a toast
// actually is so the rest of the screen stays clickable.
PanelWindow {
    id: root

    property real uiScale: 1
    // Seconds a toast stays up. Long enough to read two lines, short enough
    // that a burst does not become a wall.
    readonly property int lifeMs: 6000
    readonly property int maxShown: 3
    readonly property real toastWidth: 340

    // [{ item, born }]
    property var live: []

    function show(record) {
        const next = live.slice(0, maxShown - 1);
        next.unshift({ item: record, born: Date.now() });
        live = next;
    }

    function drop(index) {
        const next = live.slice();
        next.splice(index, 1);
        live = next;
    }

    visible: live.length > 0

    anchors { top: true; right: true }
    margins { top: 14 * uiScale; right: 14 * uiScale }

    implicitWidth: toastWidth * uiScale
    implicitHeight: Math.max(1, column.implicitHeight)

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "laser-bar-toasts"
    WlrLayershell.layer: WlrLayer.Overlay
    // Never takes the keyboard. A notification arriving must not steal a
    // keystroke from whatever you are in the middle of typing.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        width: root.visible ? root.width : 0
        height: root.visible ? root.height : 0
    }

    Column {
        id: column
        width: parent.width
        spacing: 8 * root.uiScale

        Repeater {
            model: root.live

            Rectangle {
                required property var modelData
                required property int index

                width: column.width
                height: row.implicitHeight + 18 * root.uiScale
                radius: 12 * root.uiScale
                color: "@sheetBg@"
                border.width: 1
                border.color: "@glassBorder@"
                clip: true

                Rectangle {
                    width: 2 * root.uiScale
                    height: parent.height
                    radius: width
                    color: "@greenColor@"
                }

                NotificationRow {
                    id: row
                    x: 13 * root.uiScale
                    y: 9 * root.uiScale
                    width: parent.width - 26 * root.uiScale
                    uiScale: root.uiScale
                    item: modelData.item
                }

                // Click to put it away early.
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.drop(index)
                }
            }
        }
    }

    // One sweep for all of them rather than a Timer per toast, and it only
    // runs while something is up.
    Timer {
        interval: 250
        running: root.live.length > 0
        repeat: true
        onTriggered: {
            const now = Date.now();
            const kept = root.live.filter(t => now - t.born < root.lifeMs);
            if (kept.length !== root.live.length) root.live = kept;
        }
    }
}
