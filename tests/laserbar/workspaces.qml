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
            railColor: "#FF27D796"
            workspaces: [
                { number: 1,  focused: false, icon: "code"  },
                { number: 2,  focused: false, icon: "code"  },
                { number: 3,  focused: true,  icon: "web"   },
                { number: 5,  focused: false, icon: "music" },
                { number: 10, focused: false, icon: "term"  }
            ]
        }
    }
}
