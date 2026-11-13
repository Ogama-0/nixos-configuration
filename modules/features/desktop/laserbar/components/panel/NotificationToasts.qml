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
    // How many a packed toast remembers. Past this the count still rises;
    // what you lose is being able to open them here rather than in the
    // centre, which is where a backlog belongs anyway.
    readonly property int maxInToast: 5

    // [{ items, born, leaving, app, open }] - newest item first
    property var live: []

    // A second notification from an app that already has a toast up packs
    // into it rather than opening another. Two toasts side by side saying
    // "system" is the stack telling you about itself; one saying "system
    // x2" is the stack telling you about the world. The timer restarts, so
    // a conversation keeps one toast alive instead of marching a column
    // down your screen.
    function show(record) {
        const app = record.appName || "Unknown app";
        const now = Date.now();

        for (let i = 0; i < live.length; i++) {
            if (live[i].leaving || live[i].app !== app) continue;
            const next = live.slice();
            // An OSD REPLACES its predecessor instead of packing into it.
            // Five volume presses are one reading that changed, not five
            // things that happened: a count badge and a backlog to open
            // would both be lying about what you did.
            next[i] = record.transient
                ? { items: [record], born: now, leaving: false, app: app,
                    open: false }
                : { items: [record].concat(live[i].items).slice(0, maxInToast),
                    born: now, leaving: false, app: app,
                    open: live[i].open };
            live = next;
            return;
        }

        const next = live.filter(t => !t.leaving).slice(0, maxShown - 1);
        next.unshift({ items: [record], born: now, leaving: false,
                       app: app, open: false });
        live = next;
    }

    function retire(born) {
        const next = live.map(t =>
            t.born === born
                ? { items: t.items, born: t.born, leaving: true,
                    app: t.app, open: t.open }
                : t);
        live = next;
        reaper.restart();
    }

    // Clicking a packed toast opens it where it stands, rather than making
    // you go to the centre to find out what the count was hiding. Opening
    // also stops the clock: you are reading it.
    function toggle(born) {
        const next = live.map(t =>
            t.born === born
                ? { items: t.items, born: t.open ? t.born : Date.now(),
                    leaving: false, app: t.app, open: !t.open }
                : t);
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

                    Column {
                        id: row
                        x: 13 * root.uiScale
                        y: 9 * root.uiScale
                        width: parent.width - 26 * root.uiScale
                               - (badge.visible ? badge.width + 8 * root.uiScale : 0)
                        spacing: 7 * root.uiScale

                        Repeater {
                            model: toast.modelData.open
                                ? toast.modelData.items
                                : toast.modelData.items.slice(0, 1)

                            NotificationRow {
                                required property var modelData
                                required property int index
                                width: row.width
                                uiScale: root.uiScale
                                item: modelData
                                // Named once. They are all from the same
                                // app - that is what packing means.
                                showApp: index === 0
                            }
                        }
                    }

                    // Same badge as the centre, for the same reason: only
                    // when there is more than one.
                    Rectangle {
                        id: badge
                        visible: toast.modelData.items.length > 1
                        x: parent.width - width - 13 * root.uiScale
                        y: 9 * root.uiScale
                        width: badgeText.implicitWidth + 11 * root.uiScale
                        height: badgeText.implicitHeight + 3 * root.uiScale
                        radius: height / 2
                        color: "@greenColor@"

                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: toast.modelData.items.length
                            color: "@onAccentInk@"
                            font.pixelSize: Math.round(10 * root.uiScale)
                            font.weight: Font.DemiBold
                        }
                    }

                    // Packed: click opens it. Single: click puts it away.
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (toast.modelData.items.length > 1)
                                root.toggle(toast.modelData.born);
                            else
                                root.retire(toast.modelData.born);
                        }
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
                if (!t.leaving && !t.open && now - t.born >= root.lifeMs)
                    root.retire(t.born);
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
