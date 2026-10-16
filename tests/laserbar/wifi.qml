import Quickshell
import Quickshell.Wayland
import "components"

// The wifi module, connected, three bars' worth of signal.
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

        WifiModule {
            x: 875
            y: 34 - height / 2
            coverLeft: panel.width
            coverRight: panel.width
            panelWidth: panel.width
            active: true
            ssid: "orano"
            strength: 0.8
            connected: true
        }
    }
}
