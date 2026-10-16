import Quickshell
import Quickshell.Wayland
import "components"

// One BarShell on a flat blue field. Blue so the three things under test are
// all distinguishable: the capsule fill, the near-black outline, and the
// background. With a black background the outline would be untestable.
Scope {
    PanelWindow {
        anchors { top: true; left: true; right: true }
        implicitHeight: 70
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        BarShell {
            x: 880
            y: 34 - height / 2
            bodyWidth: 120
            bodyHeight: 34
        }
    }
}
