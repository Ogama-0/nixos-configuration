import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Wifi, connected, most of the signal.
Scope {
    PanelWindow {
        id: panel
        anchors { top: true; left: true; right: true }
        implicitHeight: 70
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        BarGroup {
            x: 875
            y: 34 - height / 2
            coverLeft: panel.width
            coverRight: panel.width
            panelWidth: panel.width
            active: true
            railColor: "#FF27D796"

            WifiWidget {
                pos: 1
                ssid: "orano"
                strength: 0.8
                connected: true
            }
        }
    }
}
