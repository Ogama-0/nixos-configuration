import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// Three mounts, stubbed, the last one over the warning threshold. Not driven
// through DiskModel: that one runs df against this machine.
//
// Pane at 100,100, 74x300, uiScale 1. Bars area is 270 tall, so a bar's fill
// starts at y 100 + 270*(1-fraction):
//   62% -> y 203    38% -> y 267    88% -> y 132
// Three cells of 18.67 with 9 gaps: x 100, 128, 155.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        DiskPane {
            x: 100
            y: 100
            width: 74
            height: 300
            uiScale: 1
            freeTotal: "214 GB free"
            disks: [
                { label: "/",    usedFraction: 0.62 },
                { label: "home", usedFraction: 0.38 },
                { label: "data", usedFraction: 0.88 }
            ]
        }
    }
}
