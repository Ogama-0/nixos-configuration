import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Catches the strip mid-transition. Slowed right down through the widget's
// own public duration rather than a test-only hook, and the list is swapped
// on load, so the harness screenshot lands partway through a workspace
// opening.
Scope {
    PanelWindow {
        id: panel
        anchors { top: true; left: true; right: true }
        implicitHeight: 70
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        BarGroup {
            x: 100
            y: 34 - height / 2
            coverLeft: panel.width
            coverRight: panel.width
            panelWidth: panel.width
            active: true
            railColor: "#FF27D796"
            reservedBodyWidth: ws.reservedWidth

            WorkspaceWidget {
                id: ws
                pos: 1
                transitionDuration: 6000

                property var before: [
                    { id: 1, number: 1, focused: false, icon: "code" },
                    { id: 2, number: 2, focused: false, icon: "code" },
                    { id: 3, number: 3, focused: true,  icon: "web"  }
                ]
                property var after: [
                    { id: 1, number: 1, focused: false, icon: "code" },
                    { id: 2, number: 2, focused: false, icon: "code" },
                    { id: 3, number: 3, focused: false, icon: "web"  },
                    { id: 7, number: 7, focused: true,  icon: "chat" }
                ]

                workspaces: before

                Timer {
                    interval: 600
                    running: true
                    repeat: false
                    onTriggered: ws.workspaces = ws.after
                }
            }
        }
    }
}
