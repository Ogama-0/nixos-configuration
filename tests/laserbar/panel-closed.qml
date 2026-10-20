import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// The control panel, never summoned - the baseline the open render is diffed
// against. Identical to panel-open.qml but for the missing summon().
//
// The blue backdrop is the house fixture colour (#FF2040A0): the glass plate,
// its outline and the ground all have to be distinguishable from each other,
// and they are not against black.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
    }

    ControlPanel { id: cp }
}
