import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Open when the screen locks. The panel must dismiss rather than draw over
// the lock surface.


//

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
        Component.onCompleted: { cp.summon(); cp.lockActive = true; }
    }
}
