import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"
import "components/panel"

// The tooltip must be able to draw OUTSIDE the panel.
//
// The sheet clips its children to its rounded corners, so a tip rendered
// inside it could never cross the top edge - which is where the tip for a
// top-row tile has to go. ToggleTip is its own layer surface for exactly
// this reason, and this fixture is the proof.
//
// At uiScale 1 the panel's top edge is y=308. The tip is anchored to a
// top-row tile at y=320, so its plate lands at roughly y 290..313: straddling
// that edge, with its upper half over ground the panel cannot reach.
//
// Probe: x 560..640, y 293..301 must carry the tip's plate, not bare ground.
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

    ToggleTip {
        label: "Do not disturb"
        anchorX: 600
        anchorY: 320
        uiScale: 1
    }
}
