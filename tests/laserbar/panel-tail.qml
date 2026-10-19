import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// The panel with its tail fully extended.
//
// Probe geometry at uiScale 1 on 1920x1080. The sheet is 940 wide and the
// window 734 tall, bottom margin 38, so the window spans x 490..1430 and
// y 308..1042:
//
//   neck interior   screen x 940..990,  y 1018..1030   must be glass
//   across the mouth screen x 850..1070, y 1006..1009   must NOT carry a line
//
// The mouth band is the one that matters: the sheet's bottom edge must not
// draw across the funnel, or the tail reads as a shape hung off a closed box
// instead of part of it.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
    }

    ControlPanel {
        id: cp
        Component.onCompleted: cp.summon()
    }
}
