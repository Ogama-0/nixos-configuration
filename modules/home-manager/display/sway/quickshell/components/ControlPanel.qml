import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

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

    // Which output it is on. Empty means "the first one", which is what a
    // single-screen session and every render fixture get.
    property string targetScreen: ""

    function summon(): void {
        if (panelState === "gone") panelState = "attached";
    }
    function dismiss(): void { panelState = "gone" }
    function detach(): void {
        if (panelState === "attached") panelState = "detached";
    }
    function reattach(): void {
        if (panelState === "detached") panelState = "attached";
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

            visible: root.isOpen && onTarget

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

            PanelSheet {
                id: sheet
                uiScale: panel.uiScale
            }
        }
    }
}
