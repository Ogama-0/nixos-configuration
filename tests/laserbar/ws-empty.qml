import Quickshell
import Quickshell.Wayland
import "components"

// The workspace strip with a pinned list, so the render is the same every
// time. The live Quickshell.I3 path is wired in LaserBar.qml and exercised by
// the whole-bar fixture.
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

        WorkspaceModule {
            x: 100
            y: 34 - height / 2
            coverLeft: panel.width
            coverRight: panel.width
            panelWidth: panel.width
            active: true
            accent: "#FF27D796"
            workspaces: [
            ]
        }
    }
}
