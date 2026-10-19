import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// A phone low on battery and not charging: the bar must warn, not stay green.
// kdeconnect-cli what is on the network, and there is nothing paired here.
//
// Pane at 100,100, 262x120, uiScale 1.
//   name row    y 100..124
//   battery     y 136..152, bar at y ~158
//   the action  at the bottom
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        MobilePane {
            x: 100
            y: 100
            width: 262
            height: 120
            uiScale: 1
            connected: true
            device: { "id": "abc123", "name": "Pixel 8", "charge": 12, "charging": false }
        }
    }
}
