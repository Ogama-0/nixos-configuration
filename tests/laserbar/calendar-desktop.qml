import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// The standing desktop calendar widget, which keeps running after the panel
// gains one of its own. Its khal reading moves into CalendarModel so there
// is one parser rather than two; this fixture is how we know the move did
// not change what it draws.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
    }

    Calendar {}
}
