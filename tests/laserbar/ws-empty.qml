import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// No workspaces at all - nothing should be drawn.
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

                ]
            }
        }
    }
}
