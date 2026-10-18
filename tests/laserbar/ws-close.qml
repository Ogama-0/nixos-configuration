import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// A workspace closing: focus leaves an empty workspace, so sway destroys it
// and the strip loses a middle cell. Every surviving cell must keep its own
// width - in particular the last one, which is where an index mistake in
// settle() shows up as a workspace silently vanishing.
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

                workspaces: [
                    { id: 1, number: 1, focused: false, icon: "code" },
                    { id: 2, number: 2, focused: false, icon: "code" },
                    { id: 3, number: 3, focused: false, icon: "web" },
                    { id: 4, number: 4, focused: true,  icon: "chat" },
                    { id: 10, number: 10, focused: false, icon: "term" }
                ]

                Timer {
                    interval: 600
                    running: true
                    repeat: false
                    onTriggered: ws.workspaces = [
                        { id: 1, number: 1, focused: true,  icon: "code" },
                        { id: 2, number: 2, focused: false, icon: "code" },
                        { id: 3, number: 3, focused: false, icon: "web" },
                        { id: 10, number: 10, focused: false, icon: "term" }
                    ]
                }
            }
        }
    }
}
