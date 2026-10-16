import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

// One left-hand beam at full extent, with a pinch span over 800..1000.
// Paired with beam-nopinch.qml, which is identical but declares no spans:
// the two renders are compared to prove pinching removes strand light.
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
            pinchSpans: [[800, 1000]]
        }
    }
}
