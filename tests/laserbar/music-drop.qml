import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

// The music widget goes away under the bar, the way it does when a player
// quits: play, stop, kill the client. The capsule it shared with wifi shrinks
// by its whole width while the bar is up.
//
// The three groups are arranged exactly as LaserBar.qml arranges them -
// including the left group's `reservedBodyWidth`, which is what makes its
// drawn span differ from its item - because the bug being guarded is a
// re-entrant layout pass, and that only shows with more than one module on
// the beam.
//
// Asserted on the LOG, not on pixels: the failure is a QML binding loop on
// occupiedSpan, which Qt reports and then silently stops re-evaluating.
Scope {
    id: root
    property bool active: false

    IpcHandler {
        target: "laserbar"
        function reveal(): void { root.active = true }
        function hide(): void { root.active = false }
    }

    PanelWindow {
        id: panel
        anchors { top: true; left: true; right: true }
        implicitHeight: 70
        color: "#FF000000"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        BeamSide {
            side: "left"
            accentColor: "#FF27D796"
            active: root.active
            extent: root.active ? panel.width * 0.5 : 0
            panelWidth: panel.width
            beamY: 34
            pinchSpans: slots.moduleSpans
        }

        BeamSide {
            side: "right"
            accentColor: "#FFFF273F"
            active: root.active
            extent: root.active ? panel.width * 0.5 : 0
            panelWidth: panel.width
            beamY: 34
            pinchSpans: slots.moduleSpans
        }

        BarSlots {
            id: slots
            panelWidth: panel.width
            beamY: 34
            coverLeft: panel.width
            coverRight: panel.width
            active: true
            leftRail: "#FF27D796"
            rightRail: "#FFFF273F"
            meetX: panel.width * 0.5

            BarGroup {
                slotSide: "left"
                reservedBodyWidth: ws.reservedWidth

                WorkspaceWidget {
                    id: ws
                    pos: 1
                    workspaces: [
                        { id: 1, number: 1, focused: true,  icon: "code" },
                        { id: 2, number: 2, focused: false, icon: "web"  }
                    ]
                }
            }

            BarGroup {
                slotSide: "centre"
                ClockWidget { pos: 1 }
            }

            BarGroup {
                id: rightGroup
                slotSide: "right"

                MusicWidget {
                    id: music
                    pos: 1
                    hasPlayer: true
                    cavaFeed: false
                    title: "Mandelbrot Set"
                    artist: "Jonathan Coulton"
                    levels: [40, 70, 20, 90, 55, 30, 80, 45, 65, 25, 50]
                }

                WifiWidget {
                    pos: 2
                    ssid: "orano"
                    strength: 0.8
                    connected: true
                }
            }
        }

        // The player quits while the bar is revealed.
        Timer {
            interval: 1100
            running: true
            repeat: false
            onTriggered: music.hasPlayer = false
        }

        // Settled: report what the layout actually converged to, so a
        // re-entrant pass shows up as a span that does not match the capsule
        // it belongs to.
        Timer {
            interval: 1700
            running: true
            repeat: false
            onTriggered: {
                const spans = slots.moduleSpans.map(
                    s => "[" + Math.round(s[0]) + "," + Math.round(s[1]) + "]");
                console.log("LAYOUT spans=" + spans.join(" "));
                console.log("LAYOUT rightGroup x=" + Math.round(rightGroup.x)
                    + " shellX=" + Math.round(rightGroup.shell.x)
                    + " shellW=" + Math.round(rightGroup.shell.width)
                    + " span=" + JSON.stringify(rightGroup.occupiedSpan.map(Math.round)));
            }
        }
    }
}
