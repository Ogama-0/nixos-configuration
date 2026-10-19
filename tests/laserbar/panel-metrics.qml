import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// The three meters, stubbed to the preview's values with RAM in the warning
// band. Not driven through MetricsModel: that one reads this machine's real
// load, which is not something to assert on.
//
// Pane at 100,100, 354x90, uiScale 1. Three rows of 19 with 10 gaps, so
// row centres are y 109, 138, 167. The track starts at x 146 and is 140
// wide, so a bar's fill ends at 146 + 1.4*pct.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        MetricsPane {
            x: 100
            y: 100
            width: 354
            height: 90
            uiScale: 1
            cpuPct: 34
            gpuPct: 12
            ramPct: 71
        }
    }
}
