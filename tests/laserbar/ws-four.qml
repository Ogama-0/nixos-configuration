import Quickshell
import Quickshell.Wayland
import "components"

// Three cells, settled. Paired with workspaces.qml (five cells) to prove the
// capsule opens out to BOTH sides as cells are added, rather than only growing
// rightward from a fixed left edge.
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
            railColor: "#FF27D796"
            workspaces: [
                { id: 1, number: 1, focused: false, icon: "code" },
                { id: 2, number: 2, focused: false, icon: "code" },
                { id: 3, number: 3, focused: false, icon: "web"  },
                { id: 7, number: 7, focused: true,  icon: "chat" }
            ]
        }
    }
}
