import Quickshell
import Quickshell.Wayland
import "components"

// The clock alone, fully revealed, on a flat blue field so outline and
// background are distinguishable.
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

        ClockModule {
            x: 875
            y: 34 - height / 2
            // Fully lit: both beams have run past it.
            coverLeft: panel.width
            coverRight: panel.width
            panelWidth: panel.width
            active: true
        }
    }
}
