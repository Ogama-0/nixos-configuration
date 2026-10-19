import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
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

    readonly property int clipMs: {
        if (panelState === "gone") return dismissMode === "free" ? 190 : 220;
        if (panelState === "attached") return 280;
        return 300;
    }
    readonly property int clipEase: panelState === "gone" ? Easing.InQuart : Easing.OutQuart

    // Which output it is on. Empty means "the first one", which is what a
    // single-screen session and every render fixture get.
    property string targetScreen: ""

    function summon(): void {
        if (panelState !== "gone") return;
        // Re-arm the collapsed geometry without animating it: after a free
        // dismiss the clip is sitting at full width, and opening from there
        // would unfold from nowhere instead of out of the clock.
        snapping = true;
        dismissMode = "docked";
        animatingOut = false;
        snapping = false;
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
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
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
    SequentialAnimation {
        id: wipeAnim
        PauseAnimation { duration: 100 }
        ParallelAnimation {
            NumberAnimation { target: wipe; property: "x"; from: 0; to: 940; duration: 340 }
            SequentialAnimation {
                NumberAnimation { target: wipe; property: "alpha"; from: 0; to: 0.55; duration: 60 }
                PauseAnimation { duration: 220 }
                NumberAnimation { target: wipe; property: "alpha"; to: 0; duration: 60 }
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
        active: root.isOpen
        onLockRequested: root.lockRequested()
    }

    // shell.qml owns the lock; the panel only asks.
    signal lockRequested

    WeatherModel {
        id: weather
        active: root.isOpen
    }

    CalendarModel {
        id: cal
        active: root.isOpen
    }

    MetricsModel {
        id: metrics
        active: root.isOpen
    }

    DiskModel {
        id: diskModel
        active: root.isOpen
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

            // Bottom-anchored only, so layer-shell centres it horizontally
            // over the clock it grows out of.
            anchors.bottom: true
            margins.bottom: barHeight * uiScale

            implicitWidth: sheet.implicitWidth
            // Taller than the glass by the funnel's drop: a layer-shell
            // surface clips to itself, so the tail has to be inside this
            // window or it is simply not drawn.
            implicitHeight: sheet.implicitHeight
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "laser-bar-panel"
            WlrLayershell.layer: WlrLayer.Overlay

            // OnDemand, not Exclusive: Escape has to reach the panel, but a
            // panel left sitting there detached must not swallow keys from
            // whatever you are actually typing into underneath it.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

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

            // Takes the pointer only while it is up, like the bar does.
            mask: Region {
                width: panel.visible ? panel.width : 0
                height: panel.visible ? panel.height : 0
            }

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
                            width: 262 * zones.s; height: zones.rowSplit * zones.s }

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
                                events: cal.eventsForSelected
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
                            width: 262 * zones.s; height: (700 - 169) * zones.s }

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
