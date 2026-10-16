import Quickshell
import Quickshell.Wayland
import "components"

// Three clocks, one per slot side, to prove placement. Blue field so the gap
// between two left-slot modules is distinguishable from the capsules.
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

            ClockModule { slotSide: "left"; slotOrder: 0 }
            ClockModule { slotSide: "left"; slotOrder: 1 }
            ClockModule { slotSide: "centre" }
            ClockModule { slotSide: "right" }
        }
    }
}
