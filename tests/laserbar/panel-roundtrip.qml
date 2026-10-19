import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Summoned, undocked, then docked again. The render must be pixel-identical
// to a plain summon: anything left over is a resting binding that did not
// stand down while the transition ran.


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
        Component.onCompleted: { cp.summon(); cp.detach(); cp.reattach(); }
    }
}
