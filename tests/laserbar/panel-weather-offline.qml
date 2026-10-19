import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// The head with no fix and no network.
//
// The zone must still draw the time and say why the weather is missing -
// and then asks Open-Meteo what the weather is there, so a render through it
// a blank quarter of the panel is not an acceptable answer to "offline".
// exactly this reason.
//
// Head placed at 100,100, 570 wide, 100 tall, uiScale 1:
//   time     big Orbitron at the left   -> ink around x 110..260, y 105..150
//   temp     Orbitron at the right      -> ink around x 480..530, y 105..135
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        ClockWeatherHead {
            x: 100
            y: 100
            width: 570
            height: 100
            uiScale: 1
            timeText: "13:22"
            dateText: "Sunday 19 October"
            tempC: 15
            condition: "Clear"
            place: "Paris"
            ok: false
            failure: "No location"
        }
    }
}
