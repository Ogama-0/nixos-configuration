import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// The panel on a BLACK ground, which is what the real wallpaper is.
// the fixture opens the panel itself.
//
// The blue backdrop is the house fixture colour (#FF000000): the glass plate,
// its outline and the ground all have to be distinguishable from each other,
// and they are not against black.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF000000"
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
