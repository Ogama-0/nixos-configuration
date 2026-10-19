import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// The audio footer, stubbed. Not driven through AudioModel: that one asks
// PipeWire what this machine is plugged into.
//
// Pane at 100,100, 218 wide, uiScale 1. The device row is 20 tall and the
// slider sits at y 132, 5 tall, 218 wide - so a 58% fill ends at x 226.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        AudioPane {
            x: 100
            y: 100
            width: 218
            uiScale: 1
            deviceName: "Sennheiser HD 560S"
            volumePct: 58
            muted: false
            sinks: [
                { id: 1, name: "Built-in speakers",  isDefault: false },
                { id: 2, name: "Sennheiser HD 560S", isDefault: true },
                { id: 3, name: "HDMI - DELL U2720Q", isDefault: false }
            ]
        }
    }
}
