import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Paused: the cover has stopped turning and settled into a rounded
// square, and the wave is the flat resting line.
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
                hasPlayer: true
                playing: false
                title: "Weightless Again"
                artist: "The Handsome Family"
                artUrl: "file:///home/ogama/nixos-configuration/assets/lockscreen/nausicaa.png"
                cavaFeed: false
                levels: []
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
