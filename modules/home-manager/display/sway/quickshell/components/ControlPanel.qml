import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.I3
// The zones live one directory down; QML needs that said explicitly.
import "panel"

// The panel summoned out of the laser bar's clock: one glass sheet carrying
// the things that do not fit on a strip you can only read while a key is
// held. Zones live in components/panel/ and are added to the layout here;
// this file owns the window, the state machine and the IPC surface.
//
// Three resting states, never a pile of independent booleans:
//
//   gone      - not on screen
//   attached  - on screen, docked to the bar by the tail
//   detached  - on screen, free-standing, bar gone
//
// Transitions between them are animations, not cuts, and the rule they all
// obey is that THE PANEL ITSELF NEVER MOVES. Mod is pressed dozens of times
// an hour; a panel that lifts on every detach reads as a twitch. Only the
// tail, the bar's rails and the shadow carry the transition.
Scope {
    id: root

    // "gone" | "attached" | "detached". Not `state`: that name belongs to
    // Item, and a QML `state` carries QtQuick's own state-machine semantics.
    property string panelState: "gone"

    readonly property bool isOpen: panelState !== "gone"

    // Opening the panel used to spawn ten subprocesses in the same turn as
    // the reveal - khal, df, nmcli, bluetoothctl, powerprofilesctl, darkman,
    // two /proc reads, nvidia-smi, curl - and khal alone takes half a second
    // and then parses two hundred events back on the GUI thread. The open
    // animation is 180ms. It was being held open by work nobody was waiting
    // for yet, which is what made a press take about a second to land.
    //
    // So the panel paints first and the readers start just after. Nothing is
    // less live for it: these are things that change on the scale of
    // seconds, read for a surface you have been looking at for 150ms.
    property bool warmedUp: false
    Timer {
        id: warmUp
        interval: 150
        repeat: false
        onTriggered: root.warmedUp = true
    }
    // One handler, because QML allows exactly one per signal per object and
    // a second is a load-time error, not a warning.
    onIsOpenChanged: {
        if (isOpen) warmUp.restart();
        else {
            warmUp.stop(); warmedUp = false;
            selectedNotifications = []; selectionAnchor = "";
        }

        // sway only intercepts Escape while this mode is active, so the
        // mode's lifetime is the panel's. Leaving it on every close -
        // however the close happened - is what keeps a killed shell from
        // stranding the session in a mode nobody asked for.
        swayMode.command = ["@swaymsgBin@", "mode",
                            isOpen ? "panel" : "default"];
        swayMode.running = true;
    }

    readonly property bool readersActive: isOpen && warmedUp

    // Changing workspace dismisses the panel. Which workspace you were on
    // when it opened has to be remembered: the id changes once on open too,
    // and dismissing on that would close the panel the instant it appeared.
    readonly property int focusedWorkspace: {
        const all = I3.workspaces ? I3.workspaces.values : [];
        for (const w of all) if (w.active) return w.id;
        return -1;
    }
    property int summonedOn: -1

    onFocusedWorkspaceChanged: {
        if (!isOpen) return;
        // The I3 socket connects asynchronously, so a panel summoned early
        // in the session records -1 and would then never dismiss on a
        // workspace change at all. Adopt the first id we actually learn
        // instead of treating "not known yet" as "never leave".
        if (summonedOn === -1) { summonedOn = focusedWorkspace; return; }
        if (focusedWorkspace !== summonedOn) dismiss();
    }


    // Set by shell.qml from the bar. Releasing mod hides the bar and the
    // panel undocks; holding it again re-docks. Without this the detach and
    // re-attach animations exist and nothing ever plays them - they were
    // dead code for the whole first pass.
    property bool barVisible: false
    onBarVisibleChanged: {
        if (!isOpen) return;
        if (barVisible) reattach(); else detach();
    }

    // Set by shell.qml from the lock surface. An open panel drawn over a
    // locked screen would leak the calendar and the notification list past
    // the lock, so it goes.
    property bool lockActive: false
    onLockActiveChanged: if (lockActive) dismiss()

    // How the last dismissal was asked for, which decides which of the two
    // closing animations plays. Docked collapses back into the clock;
    // detached cannot, because there is no clock on screen to collapse into
    // - a retreat into nothing - so it sinks and fades instead.
    property string dismissMode: "docked"
    property bool animatingOut: false

    // Suppresses the Behaviors for one assignment, so re-arming the closed
    // geometry before an open does not animate a collapse nobody sees.
    property bool snapping: false

    // ---- the clip, in 1080p-equivalent units ----
    //
    // ONE animated inset rectangle drives every docked transition, because
    // the sheet and the funnel are a single Shape (PanelSheet.qml) and a
    // clip is the only way to reveal part of one:
    //
    //   attached   0..940 x 0..734   sheet and funnel
    //   detached   0..940 x 0..700   the funnel clipped away, sheet untouched
    //   gone       406..534 x 700..734   the neck stub, i.e. the clock
    //
    // Collapsing to that last box IS the dock-dismiss: the panel folds back
    // into the clock it came out of.
    readonly property bool collapsing: panelState === "gone" && dismissMode === "docked"
    readonly property bool sinking: panelState === "gone" && dismissMode === "free"

    property real clipL: collapsing ? 406 : 0
    property real clipR: collapsing ? 534 : 940
    property real clipT: collapsing ? 700 : 0
    property real clipB: (panelState === "attached" || collapsing) ? 734 : 700

    property real sheetOpacity: sinking ? 0 : 1
    property real sheetScale: sinking ? 0.965 : 1

    // Zones bind this so content fades up with the sheet rather than
    // appearing fully formed inside a box that is still opening.
    property real contentReveal: isOpen ? 1 : 0

    // Short on purpose. This opens dozens of times an hour and the only
    // thing that matters is that it feels instant; 280ms measured fine and
    // read as sluggish, which is the only verdict that counts.
    //
    // Nothing waits for anything else: these are Behaviors, so a summon
    // during a dismiss retargets from wherever the clip currently is rather
    // than queueing behind it.
    readonly property int clipMs: {
        if (panelState === "gone") return dismissMode === "free" ? 140 : 150;
        if (panelState === "attached") return 180;
        return 200;
    }
    // OutQuint opens: almost all the distance is covered in the first third,
    // so it reads as arriving rather than travelling.
    readonly property int clipEase: panelState === "gone" ? Easing.InQuad : Easing.OutQuint

    // Which output it is on. Empty means "the first one", which is what a
    // single-screen session and every render fixture get.
    property string targetScreen: ""

    function summon(): void {
        if (panelState !== "gone") return;
        // Only re-arm after a FREE dismiss, where the clip is parked at full
        // width and opening from there would unfold from nowhere. After a
        // docked dismiss the clip is already collapsed at the clock, and
        // snapping would throw away a half-finished close that the Behavior
        // can simply reverse - which is what makes a fast mod+n,Escape,mod+n
        // feel continuous instead of stuttering.
        if (dismissMode === "free") {
            snapping = true;
            dismissMode = "docked";
            snapping = false;
        }
        animatingOut = false;
        summonedOn = focusedWorkspace;
        panelState = "attached";
        wipe.restart();
    }
    function dismiss(): void {
        if (panelState === "gone") return;
        dismissMode = panelState === "detached" ? "free" : "docked";
        animatingOut = true;
        panelState = "gone";
        outTimer.interval = clipMs;
        outTimer.restart();
    }

    Process { id: swayMode }

    // Keeps the window up until the closing animation has finished; without
    // it the surface vanishes on the first frame and there is no animation
    // to see at all.
    Timer {
        id: outTimer
        repeat: false
        onTriggered: root.animatingOut = false
    }

    Behavior on clipL { enabled: !root.snapping; NumberAnimation { duration: root.clipMs; easing.type: root.clipEase } }
    Behavior on clipR { enabled: !root.snapping; NumberAnimation { duration: root.clipMs; easing.type: root.clipEase } }
    Behavior on clipT { enabled: !root.snapping; NumberAnimation { duration: root.clipMs; easing.type: root.clipEase } }
    Behavior on clipB { enabled: !root.snapping; NumberAnimation { duration: root.clipMs; easing.type: root.clipEase } }
    Behavior on sheetOpacity { enabled: !root.snapping; NumberAnimation { duration: root.clipMs; easing.type: root.clipEase } }
    Behavior on sheetScale { enabled: !root.snapping; NumberAnimation { duration: root.clipMs; easing.type: root.clipEase } }
    Behavior on contentReveal {
        enabled: !root.snapping
        NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
    }

    // The laser wipe: one accent line crossing the sheet as it opens, the
    // same gesture the bar's own reveal makes. Transient by nature - it is
    // over long before the render harness screenshots, so no probe pins it.
    QtObject {
        id: wipe
        property real x: 0
        property real alpha: 0
        function restart(): void { wipeAnim.restart() }
    }
    // Crosses WITH the panel opening, not after it. Trailing behind the
    // reveal is what made the whole thing read as two separate events.
    SequentialAnimation {
        id: wipeAnim
        PauseAnimation { duration: 20 }
        ParallelAnimation {
            NumberAnimation { target: wipe; property: "x"; from: 0; to: 940; duration: 200 }
            SequentialAnimation {
                NumberAnimation { target: wipe; property: "alpha"; from: 0; to: 0.5; duration: 40 }
                PauseAnimation { duration: 110 }
                NumberAnimation { target: wipe; property: "alpha"; to: 0; duration: 50 }
            }
        }
    }
    function detach(): void {
        if (panelState === "attached") panelState = "detached";
    }
    function reattach(): void {
        if (panelState === "detached") panelState = "attached";
    }

    // Non-visual, so it lives at the Scope: one set of backends for the
    // panel, not one per output.
    ToggleModel {
        id: toggles
        active: root.readersActive
        onLockRequested: root.lockRequested()
    }

    // shell.qml owns the lock; the panel only asks.
    signal lockRequested

    WeatherModel {
        id: weather
        active: root.readersActive
    }

    CalendarModel {
        id: cal
        active: root.readersActive
    }

    MetricsModel {
        id: metrics
        active: root.readersActive
    }

    DiskModel {
        id: diskModel
        active: root.readersActive
    }

    // NOT gated on isOpen. A centre that only listened while you were
    // looking at it would be a list of things you had already seen.
    // Selection and expansion live HERE, not in the pane. The pane sits
    // inside a Variants delegate - one per screen - and ids in there are
    // invisible to the IPC handler, which is how the Delete key spent a
    // release calling into a `notifyPane` that did not exist. Keeping the
    // state outside also stops two screens disagreeing about it.
    property var selectedNotifications: []
    property string selectionAnchor: ""
    property var expandedGroups: ({})

    // The notifications as they are actually laid out: groups in order,
    // a collapsed one contributing only its newest entry. Range selection
    // and "select the next one after a delete" both need to agree with
    // what you can see, not with the underlying list.
    // Pure, so it can be tested with a literal instead of a bus.
    function visibleOrderOf(gs, open) {
        const out = [];
        for (let i = 0; i < gs.length && i < 5; i++) {
            const g = gs[i];
            if (open[g.key] === true)
                for (const it of g.items.slice(0, 6)) out.push(it.uid);
            else
                out.push(g.items[0].uid);
        }
        return out;
    }

    function visibleOrder() {
        return visibleOrderOf(notifications.groups, expandedGroups);
    }

    // What to land on once `doomed` is gone: the first survivor below the
    // selection, or failing that the last one above it. Pure, same reason.
    function nextAfter(order, doomed) {
        let after = "";
        for (let i = order.length - 1; i >= 0; i--) {
            if (doomed.indexOf(order[i]) >= 0) break;
            after = order[i];
        }
        if (after === "") {
            for (const uid of order) {
                if (doomed.indexOf(uid) >= 0) break;
                after = uid;
            }
        }
        return after;
    }

    // Also pure: what a click should leave selected.
    function selectionFor(order, current, anchor, uid, extend) {
        if (extend && anchor !== "") {
            const a = order.indexOf(anchor), b = order.indexOf(uid);
            if (a >= 0 && b >= 0)
                return order.slice(Math.min(a, b), Math.max(a, b) + 1);
        }
        if (current.length === 1 && current[0] === uid) return [];
        return [uid];
    }

    function toggleGroup(key) {
        const next = {};
        for (const k in expandedGroups) next[k] = expandedGroups[k];
        next[key] = !next[key];
        expandedGroups = next;
    }

    // Plain click selects one. Shift extends from the anchor across
    // everything between, in the order you see them.
    function selectNotification(uid, extend) {
        const next = selectionFor(visibleOrder(), selectedNotifications,
                                  selectionAnchor, uid, extend);
        selectedNotifications = next;
        if (next.length !== 1 || next[0] !== uid) {
            if (next.length === 0) selectionAnchor = "";
        } else {
            selectionAnchor = uid;
        }
    }

    NotificationServer {
        id: notifications
        dnd: toggles.dndOn
        onPosted: record => toasts.show(record)
    }

    NotificationToasts {
        id: toasts
        uiScale: 1
    }

    AudioModel {
        id: audio
        active: root.readersActive
    }

    MobileModel {
        id: mobile
        active: root.readersActive
    }

    // The panel's own clock. One tick a second, and only while it is open -
    // the bar's clock learned this the expensive way.
    property var now: new Date()
    Timer {
        interval: 1000
        running: root.isOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // Hovering a tile names it. The tip is a separate layer surface, placed
    // in screen coordinates, because the sheet clips its own children.
    ToggleTip {
        id: tip
        label: ""
        uiScale: 1
    }

    IpcHandler {
        target: "panel"
        function open(): void { root.summon() }
        function dismiss(): void { root.dismiss() }
        function toggle(): void {
            if (root.isOpen) root.dismiss(); else root.summon();
        }
        // Bound to mod+shift+z, which used to be makoctl dismiss.
        function clearNotifications(): void { notifications.clearAll() }
        // Delete, while the panel is up. Does nothing with no selection.
        // Deletes everything selected and lands on what follows, so a
        // backlog can be cleared with one finger on the key instead of a
        // click between every press.
        function deleteSelected(): void {
            const doomed = root.selectedNotifications;
            if (doomed.length === 0) return;

            const after = root.nextAfter(root.visibleOrder(), doomed);

            for (const uid of doomed) notifications.dismissUid(uid);
            root.selectedNotifications = after === "" ? [] : [after];
            root.selectionAnchor = after;
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel

            required property var modelData
            screen: modelData

            readonly property bool onTarget:
                root.targetScreen === ""
                    ? modelData === Quickshell.screens[0]
                    : modelData.name === root.targetScreen

            visible: (root.isOpen || root.animatingOut) && onTarget

            // Full-screen, not sheet-sized. Three of the four ways out need
            // it: a click lands outside the sheet, Escape needs keyboard
            // focus, and neither reaches a surface that only covers the
            // sheet. The wallpaper picker is the same shape for the same
            // reason. The sheet is positioned inside it by `stage` below.
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "laser-bar-panel"
            WlrLayershell.layer: WlrLayer.Overlay

            // OnDemand: the compositor hands the keyboard over when the
            // surface is CLICKED, and not before.
            //
            // This is the only setting that allows shift-click. Wayland
            // delivers keyboard modifiers over wl_keyboard, which only the
            // surface holding keyboard focus receives - with None the panel
            // was told about every click and never about Shift, so a range
            // selection could not be detected at all. Not a bug in the
            // handler; the information was never sent.
            //
            // What it costs: once you have clicked the panel, keystrokes go
            // to it until you dismiss it or click away. Summoning it and
            // not touching it leaves your typing where it was.
            //
            // Escape and Delete do not depend on this either way - sway
            // intercepts those two in modes.panel and passes everything
            // else through to the focused window.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            focusable: true

            // The clock capsule is 38 tall centred on beamY, which puts its
            // top 44 1080p-pixels above the screen bottom (LaserBar.qml:
            // 70 tall, beamY = 45 from its top). The funnel's neck ends at
            // 38, so it runs 6px behind the capsule - which is what hides
            // the two flank strokes where they terminate.
            readonly property real barHeight: 38

            // Same derivation as LaserBar's, deliberately repeated rather
            // than shared: a singleton for four lines would cost a file, a
            // treeFor entry and an import in every consumer. LASERBAR_UI_SCALE
            // pins it so the render tests can check a size without that display.
            readonly property real uiScale: {
                const forced = parseFloat(Quickshell.env("LASERBAR_UI_SCALE"));
                if (!isNaN(forced) && forced > 0) return forced;
                const h = screen ? screen.height : 1080;
                return Math.max(1, Math.min(3, h / 1080));
            }

            // No input mask at all, deliberately. The whole surface takes
            // the pointer while it is up, which is what lets the backdrop
            // below catch a click anywhere outside the sheet; the surface
            // does not exist at all when the panel is shut, so there is
            // nothing to mask off. A Region sized to the window LOOKS
            // equivalent and is not - it cost an afternoon.

            // Click anywhere that is not the sheet.
            MouseArea {
                // Sized from the WINDOW, not `anchors.fill: parent`. This
                // window's content item stays 0x0, so anything anchored to
                // it is 0x0 too and silently receives no pointer events at
                // all - the panel drew perfectly while being completely
                // unclickable. `stage` below only escaped it by doing its
                // own arithmetic against panel.width/height.
                width: panel.width
                height: panel.height
                // Tested against the sheet's rectangle rather than trusting
                // z-order and event propagation: the zones do not cover
                // every pixel of the sheet - the gaps between tiles, the
                // metrics column, the mobile stub have no MouseArea of
                // their own - so a click on any of those fell through to
                // here and shut the panel you were using.
                onClicked: e => {
                    if (e.x >= stage.x && e.x <= stage.x + stage.width
                        && e.y >= stage.y && e.y <= stage.y + stage.height)
                        return;
                    root.dismiss();
                }
            }

            Item {
                // Same reason as the backdrop above.
                width: panel.width
                height: panel.height
                focus: true
                Keys.onEscapePressed: root.dismiss()
            }

            // Where the sheet actually sits now that the window is the whole
            // output: horizontally centred, its bottom edge clearing the bar
            // so the funnel has somewhere to run.
            Item {
                id: stage
                width: sheet.implicitWidth
                height: sheet.implicitHeight
                x: Math.round((panel.width - width) / 2)
                y: Math.round(panel.height - height
                              - panel.barHeight * panel.uiScale)

            // The clipper is what moves; the sheet inside it is pinned by an
            // equal and opposite offset so the glass never shifts on screen.
            // That is the hard rule: mod is pressed dozens of times an hour
            // and a panel that jumps on every dock reads as a twitch.
            Item {
                id: clipper
                clip: true
                x: root.clipL * panel.uiScale
                y: root.clipT * panel.uiScale
                width: (root.clipR - root.clipL) * panel.uiScale
                height: (root.clipB - root.clipT) * panel.uiScale
                opacity: root.sheetOpacity
                scale: root.sheetScale
                transformOrigin: Item.Center

                PanelSheet {
                    id: sheet
                    uiScale: panel.uiScale
                    // Closes as the funnel goes, so the outline is complete
                    // the whole time rather than briefly open at the mouth.
                    mouthClosed: root.panelState === "detached" ? 1 : 0
                    Behavior on mouthClosed {
                        NumberAnimation { duration: root.clipMs
                                          easing.type: root.clipEase }
                    }
                    x: -clipper.x
                    y: -clipper.y

                    Rectangle {
                        width: 3 * panel.uiScale
                        height: parent.height
                        x: wipe.x * panel.uiScale
                        color: "@greenColor@"
                        opacity: wipe.alpha
                    }

                    // ---- the layout ----
                    //
                    // Explicit arithmetic in 1080p units, not a RowLayout:
                    // positioners are forbidden for anything that animates
                    // (docs/adding-a-bar-widget.md rule 5), and the whole
                    // sheet animates on every summon.
                    //
                    //   0        322   677      940
                    //   +---------+-----+--------+   168   toggles | metrics | mobile
                    //   +-----------+---+--------+         calendar | disks | notifications
                    //   0          570 677      940
                    //
                    // The right column's two zones share an edge at 678 so
                    // mobile sits exactly above notifications.
                    Item {
                        id: zones
                        x: 0; y: 0
                        width: 940 * panel.uiScale
                        height: 700 * panel.uiScale
                        opacity: root.contentReveal

                        readonly property real s: panel.uiScale
                        readonly property real rowSplit: 168

                        Item { id: toggleZone
                            x: 0; y: 0
                            width: 322 * zones.s; height: zones.rowSplit * zones.s

                            ToggleGrid {
                                x: 22 * zones.s
                                y: 18 * zones.s
                                width: parent.width - 44 * zones.s
                                height: parent.height - 36 * zones.s
                                uiScale: panel.uiScale
                                items: toggles.items

                                onActivated: key => toggles.act(key)
                                // Tile coordinates are grid-local; the tip
                                // needs them on the screen, so they are
                                // walked out through the zone, the sheet and
                                // the window's own margins.
                                onTileHovered: (key, cx, ty, entered) => {
                                    if (!entered) { tip.label = ""; return; }
                                    const gx = panel.x + toggleZone.x + 22 * zones.s;
                                    const gy = panel.y + toggleZone.y + 18 * zones.s;
                                    tip.uiScale = panel.uiScale;
                                    tip.anchorX = gx + cx;
                                    tip.anchorY = gy + ty;
                                    tip.label = toggles.items.find(i => i.key === key).name;
                                }
                            }
                        }
                        Item { id: metricZone
                            x: 323 * zones.s; y: 0
                            width: 354 * zones.s; height: zones.rowSplit * zones.s

                            MetricsPane {
                                x: 20 * zones.s
                                y: 34 * zones.s
                                width: parent.width - 40 * zones.s
                                height: 90 * zones.s
                                uiScale: panel.uiScale
                                cpuPct: metrics.cpuPct
                                gpuPct: metrics.gpuPct
                                ramPct: metrics.ramPct
                            }
                        }
                        Item { id: mobileZone
                            x: 678 * zones.s; y: 0
                            width: 262 * zones.s; height: zones.rowSplit * zones.s

                            MobilePane {
                                x: 22 * zones.s
                                y: 26 * zones.s
                                width: parent.width - 44 * zones.s
                                height: parent.height - 52 * zones.s
                                uiScale: panel.uiScale
                                device: mobile.device
                                connected: mobile.connected
                                // Both of these put a window on screen, and
                                // a layer-shell overlay is above every
                                // normal window by protocol - the dialog
                                // would open BEHIND the panel and be
                                // unreachable. Standing down is the only
                                // way it can be used, and the panel's job
                                // is finished the moment you have asked.
                                onGuiAsked: { mobile.openGui(); root.dismiss(); }
                                onFileAsked: { mobile.sendFile(); root.dismiss(); }
                                // Clipboard opens nothing, so the panel stays.
                                onClipboardAsked: mobile.sendClipboard()
                            }
                        }

                        Item { id: calendarZone
                            x: 0; y: 169 * zones.s
                            width: 570 * zones.s; height: (700 - 169) * zones.s

                            ClockWeatherHead {
                                x: 22 * zones.s
                                y: 18 * zones.s
                                width: parent.width - 44 * zones.s
                                height: 100 * zones.s
                                uiScale: panel.uiScale

                                timeText: Qt.formatTime(root.now, "HH:mm")
                                dateText: Qt.formatDate(root.now, "dddd d MMMM")
                                tempC: weather.tempC
                                condition: weather.condition
                                place: weather.place
                                ok: weather.ok
                                failure: weather.failure
                            }

                            CalendarPane {
                                x: 22 * zones.s
                                y: 128 * zones.s
                                width: parent.width - 44 * zones.s
                                height: parent.height - 146 * zones.s
                                uiScale: panel.uiScale

                                monthLabel: cal.monthLabel
                                cells: cal.monthCells
                                events: cal.visibleEvents
                                emptyText: !cal.onToday ? "Nothing on."
                                    : cal.todayHadEvents
                                        ? "No more events today."
                                        : "Nothing on today."
                                onToday: cal.onToday
                                selectedLabel: cal.onToday
                                    ? "Today"
                                    : Qt.formatDate(cal.selected, "dddd d MMMM")

                                onPrevMonth: cal.shiftMonth(-1)
                                onNextMonth: cal.shiftMonth(1)
                                onTodayAsked: cal.goToday()
                                onDaySelected: d => cal.selectDay(d)
                            }
                        }
                        Item { id: diskZone
                            x: 571 * zones.s; y: 169 * zones.s
                            width: 106 * zones.s; height: (700 - 169) * zones.s

                            DiskPane {
                                x: 16 * zones.s
                                y: 18 * zones.s
                                width: parent.width - 32 * zones.s
                                height: parent.height - 36 * zones.s
                                uiScale: panel.uiScale
                                disks: diskModel.disks
                                freeTotal: diskModel.freeTotal
                            }
                        }
                        Item { id: notifyZone
                            x: 678 * zones.s; y: 169 * zones.s
                            width: 262 * zones.s; height: (700 - 169) * zones.s

                            NotificationPane {
                                x: 22 * zones.s
                                y: 18 * zones.s
                                width: parent.width - 44 * zones.s
                                height: parent.height - 36 * zones.s
                                uiScale: panel.uiScale
                                groups: notifications.groups
                                selectedUids: root.selectedNotifications
                                expanded: root.expandedGroups
                                onSelectRequested: (uid, extend) =>
                                    root.selectNotification(uid, extend)
                                onToggleRequested: key => root.toggleGroup(key)

                                onClearAllAsked: notifications.clearAll()
                                onGroupCleared: app => notifications.dismissGroup(app)
                                onDismissed: item => notifications.dismiss(item)

                                // Audio is the pane's footer slot, so the
                                // beam between them belongs to the pane and
                                // moves with the list.
                                AudioPane {
                                    width: parent.width
                                    uiScale: panel.uiScale
                                    sinks: audio.sinks
                                    deviceName: audio.defaultName
                                    volumePct: audio.volumePct
                                    muted: audio.muted

                                    onVolumeAsked: pct => audio.setVolume(pct)
                                    onMuteAsked: audio.toggleMute()
                                    onCycleAsked: {
                                        const s = audio.sinks;
                                        let i = s.findIndex(x => x.isDefault);
                                        audio.setSink(s[(i + 1) % s.length].id);
                                    }
                                }
                            }
                        }

                        PanelBeam { x: 322 * zones.s; y: 14 * zones.s
                            height: (zones.rowSplit - 28) * zones.s }
                        PanelBeam { x: 677 * zones.s; y: 14 * zones.s
                            height: (zones.rowSplit - 28) * zones.s }
                        PanelBeam { horizontal: true
                            x: 30 * zones.s; y: zones.rowSplit * zones.s
                            width: (940 - 60) * zones.s }
                        PanelBeam { x: 570 * zones.s; y: 190 * zones.s
                            height: (700 - 190 - 24) * zones.s }
                        PanelBeam { x: 677 * zones.s; y: 190 * zones.s
                            height: (700 - 190 - 24) * zones.s }
                    }
                }
            }
            }
        }
    }
}
