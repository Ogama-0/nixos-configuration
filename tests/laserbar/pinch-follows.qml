import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

// The strip grows after the bar has laid out, with a real beam behind it.
// The strands must collapse around the capsule's NEW extent, not the one it
// had when the bar started.
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
            extent: root.active ? panel.width : 0
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

            BarGroup {
                slotSide: "left"
                reservedBodyWidth: ws.reservedWidth

                WorkspaceWidget {
                    id: ws
                    pos: 1
                    workspaces: [{ id: 1, number: 1, focused: true, icon: "code" }]

                    Timer {
                        interval: 700
                        running: true
                        repeat: false
                        onTriggered: ws.workspaces = [
                            { id: 1, number: 1,  focused: true,  icon: "code"  },
                            { id: 2, number: 2,  focused: false, icon: "code"  },
                            { id: 3, number: 3,  focused: false, icon: "web"   },
                            { id: 5, number: 5,  focused: false, icon: "music" },
                            { id: 10, number: 10, focused: false, icon: "term" }
                        ]
                    }
                }
            }
        }
    }
}
