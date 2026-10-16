import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

// A rail whose amplitude comes from amplitudeAt rather than the constant.
// The low-signal half of that pair.
Scope {
    id: root
    property bool active: false

    IpcHandler {
        target: "laserbar"
        function reveal(): void { root.active = true }
        function hide(): void { root.active = false }
    }

    PanelWindow {
        id: panel
        anchors { top: true; left: true; right: true }
        implicitHeight: 70
        color: "#FF000000"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        BeamSide {
            side: "left"
            accentColor: "#FF27D796"
            active: root.active
            extent: root.active ? panel.width : 0
            panelWidth: panel.width
            beamY: 34
            amplitudeAt: function (px, s) { return 2 + (s % 3) * 0.5; }
        }
    }
}
