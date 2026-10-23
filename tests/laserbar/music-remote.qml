import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// The mini music widget playing the PHONE's track, over kdeconnect: the
// phone mark on the right of the capsule, and a wave fed by RemoteSpectrum
// because the phone's audio never reaches this machine for cava to read.
//
// `levels` is left empty on purpose - the remote path must not fall back to
// the cava feed, and this fixture is how that stays true.
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
                playing: true
                title: "Weightless Again"
                artist: "The Handsome Family"
                artUrl: ""
                cavaFeed: false
                levels: []
                remote: true
                remoteLevels: [10, 42, 88, 61, 30, 74, 95, 52, 18, 66]
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
