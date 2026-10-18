import Quickshell
import Quickshell.Wayland
import "components"

// Four groups across the three sides, to prove placement and spacing.
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

        BarSlots {
            panelWidth: panel.width
            beamY: 34
            coverLeft: panel.width
            coverRight: panel.width
            active: true
            leftRail: "#FF27D796"
            rightRail: "#FFFF273F"

            BarGroup { slotSide: "left";   slotOrder: 0; ClockWidget { pos: 1 } }
            BarGroup { slotSide: "left";   slotOrder: 1; ClockWidget { pos: 1 } }
            BarGroup { slotSide: "centre"; ClockWidget { pos: 1 } }
            BarGroup { slotSide: "right";  ClockWidget { pos: 1 } }
        }
    }
}
