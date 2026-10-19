import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Summoned, then undocked. The sheet must still be painted in full and the
// funnel must be gone - that is the whole visible difference between the two
// docked states, because the panel itself never moves.
//
// Neck probe at uiScale 1 on 1920x1080: screen x 940..990, y 1018..1030.
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
        Component.onCompleted: { cp.summon(); cp.detach(); }
    }
}
