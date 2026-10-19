import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// The panel's zone dividers.
//
// The zones are separated by beams and by nothing else - no cards, no per-zone
// backgrounds. So the beams ARE the layout: if they are at the right x and y,
// the zones are too, and probing them needs no test-only code inside the panel.
//
// Divider positions at uiScale 1 on 1920x1080 (window origin 490,308):
//
//   top-row vertical    sheet x 322 -> screen 812
//   top-row vertical    sheet x 677 -> screen 1167
//   row divider         sheet y 168 -> screen 476
//   bottom-row vertical sheet x 570 -> screen 1060
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
        Component.onCompleted: cp.summon()
    }
}
