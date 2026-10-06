import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// The laser bar itself: battery-driven beams from each screen edge, a
// collision payoff where they meet, and whatever bar modules are listed at
// the bottom of PanelWindow. Beam/collision visuals live in BeamSide.qml
// and CollisionEffects.qml; each module is self-contained (see
// ClockModule.qml and, underneath it, GlassPill.qml for the shared
// template) - adding or removing one is a single block below, nothing
// elsewhere needs to change.
Scope {
    id: root

    property bool active: false
    property real batteryFraction: 0.5

    IpcHandler {
        target: "laserbar"
        function reveal(): void { root.active = true }
        function hide(): void { root.active = false }
    }

    Process {
        id: batteryProc
        command: ["bash", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseFloat(this.text.trim())
                root.batteryFraction = isNaN(value) ? 0.5 : value / 100
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: batteryProc.running = true
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel

            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 70
            color: "transparent"
            focusable: false
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}

            // Vertical center of the whole bar, pinned near the panel's top
            // edge rather than the window's own vertical center, so the bar
            // hugs the very top of the screen.
            readonly property real beamY: 34

            // Current travel distance of each beam from its screen edge,
            // shared by the beams, the collision meeting point, and every
            // module's reveal-mask sync.
            property real leftExtent: root.active ? root.batteryFraction * width : 0
            property real rightExtent: root.active ? (1 - root.batteryFraction) * width : 0

            Behavior on leftExtent {
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }
            Behavior on rightExtent {
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }

            WlrLayershell.namespace: "laser-bar"
            WlrLayershell.layer: WlrLayer.Overlay

            BeamSide {
                side: "left"
                accentColor: "@greenColor@"
                active: root.active
                extent: panel.leftExtent
                panelWidth: panel.width
                beamY: panel.beamY
            }

            BeamSide {
                side: "right"
                accentColor: "@redColor@"
                active: root.active
                extent: panel.rightExtent
                panelWidth: panel.width
                beamY: panel.beamY
            }

            CollisionEffects {
                active: root.active
                meetX: root.batteryFraction * panel.width
                panelWidth: panel.width
                beamY: panel.beamY
            }

            // ── Modules ──────────────────────────────────────────────
            // Add or remove a module by adding/removing one block here.
            // Every module needs coverLeft/coverRight/panelWidth so its
            // GlassPill/RevealMask reveals in sync with the beams;
            // everything else (size, position, content) is the module's
            // own concern.

            ClockModule {
                coverLeft: panel.leftExtent
                coverRight: panel.rightExtent
                panelWidth: panel.width
                active: root.active
                anchors.horizontalCenter: parent.horizontalCenter
                y: panel.beamY - height / 2
            }
        }
    }
}
