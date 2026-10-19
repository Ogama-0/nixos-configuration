import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Nothing playing: the music widget takes no width at all and the right
// capsule is the wifi readout alone.
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
            x: 600
            y: 34 - height / 2
            coverLeft: panel.width
            coverRight: panel.width
            panelWidth: panel.width
            active: true
            railColor: "#FFE05263"

            MusicWidget {
                pos: 1
                hasPlayer: false
                cavaFeed: false
            }

            WifiWidget {
                pos: 2
                ssid: "orano"
                strength: 0.8
                connected: true
            }
        }
    }
}
