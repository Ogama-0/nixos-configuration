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
//
// The arrival is where this thing spends its character. A toast flies in
// from off-screen right and overshoots slightly, and its accent edge is
// DRAWN down the side as it lands - the bar's own beam, doing the one
// gesture the bar does. Everything else stays quiet so that reads.
PanelWindow {
    id: root

    property real uiScale: 1
    readonly property int lifeMs: 6000
    readonly property int maxShown: 3
    readonly property real toastWidth: 340

    // Removal is two-phase: mark, animate, then drop. Splicing the entry
    // out on the spot destroys its delegate mid-frame and there is nothing
    // left to animate - toasts would simply blink out of existence.
    readonly property int exitMs: 200

    // [{ item, born, leaving }]
    property var live: []

    function show(record) {
        const next = live.filter(t => !t.leaving).slice(0, maxShown - 1);
        next.unshift({ item: record, born: Date.now(), leaving: false });
        live = next;
    }

    function retire(born) {
        const next = live.map(t =>
            t.born === born ? { item: t.item, born: t.born, leaving: true } : t);
        live = next;
        reaper.restart();
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

        // When one toast goes, the ones below slide up into the gap rather
        // than jumping.
        move: Transition {
            NumberAnimation { properties: "y"; duration: 180
                              easing.type: Easing.OutCubic }
        }

        Repeater {
            model: root.live

            Item {
                id: toast
                required property var modelData
                required property int index

                width: column.width
                height: plate.height

                // A delegate can be rebuilt when the list changes, and
                // replaying the arrival for every toast every time anything
                // arrives would be a mess. Only something genuinely new
                // flies in; a rebuilt one is simply already there.
                readonly property bool fresh:
                    Date.now() - modelData.born < 150

                Rectangle {
                    id: plate
                    width: parent.width
                    height: row.implicitHeight + 18 * root.uiScale
                    radius: 12 * root.uiScale
                    color: "@sheetBg@"
                    border.width: 1
                    border.color: "@glassBorder@"
                    clip: true

                    // The beam, drawn down the edge as the toast lands.
                    Rectangle {
                        id: beam
                        width: 2 * root.uiScale
                        height: parent.height
                        radius: width
                        color: "@greenColor@"
                        transformOrigin: Item.Top
                        scale: 1
                    }

                    NotificationRow {
                        id: row
                        x: 13 * root.uiScale
                        y: 9 * root.uiScale
                        width: parent.width - 26 * root.uiScale
                        uiScale: root.uiScale
                        item: toast.modelData.item
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.retire(toast.modelData.born)
                    }
                }

                // ---- arrival ----
                ParallelAnimation {
                    id: flyIn
                    running: toast.fresh && !toast.modelData.leaving
                    // OutBack overshoots a little past the resting place and
                    // settles. That overshoot is the whole personality.
                    NumberAnimation {
                        target: toast; property: "x"
                        from: root.toastWidth * root.uiScale + 20; to: 0
                        duration: 320; easing.type: Easing.OutBack
                        easing.overshoot: 1.5
                    }
                    NumberAnimation {
                        target: toast; property: "opacity"
                        from: 0; to: 1; duration: 140
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 90 }
                        NumberAnimation {
                            target: beam; property: "scale"
                            from: 0; to: 1
                            duration: 220; easing.type: Easing.OutCubic
                        }
                    }
                }

                // ---- departure ----
                ParallelAnimation {
                    running: toast.modelData.leaving
                    NumberAnimation {
                        target: toast; property: "x"
                        to: root.toastWidth * root.uiScale * 0.4
                        duration: root.exitMs; easing.type: Easing.InCubic
                    }
                    NumberAnimation {
                        target: toast; property: "opacity"
                        to: 0; duration: root.exitMs
                    }
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
            for (const t of root.live)
                if (!t.leaving && now - t.born >= root.lifeMs) root.retire(t.born);
        }
    }

    // Clears out whatever has finished its exit animation.
    Timer {
        id: reaper
        interval: root.exitMs + 40
        repeat: false
        onTriggered: root.live = root.live.filter(t => !t.leaving)
    }
}
