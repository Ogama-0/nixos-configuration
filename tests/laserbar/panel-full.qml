import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Every zone, live, attached to the bar. The one fixture that is NOT stubbed:
// it renders whatever this machine actually reports, so it is for looking at
// next to docs/previews/laser-bar-panel.html rather than for probing values.
//
// Render both variants:
//   scripts/laserbar-preview.sh tests/laserbar/panel-full.qml /tmp/dark.png 0.62
//   LASERBAR_VARIANT=light scripts/laserbar-preview.sh tests/laserbar/panel-full.qml /tmp/light.png 0.62
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
    }

    LaserBar { id: bar }

    ControlPanel {
        id: cp
        Component.onCompleted: cp.summon()
    }
}
