import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Five workspaces, the third focused.
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
                    { id: 3, number: 3, focused: true, icon: "web" },
                    { id: 5, number: 5, focused: false, icon: "music" },
                    { id: 10, number: 10, focused: false, icon: "term" }
                ]
            }
        }
    }
}
