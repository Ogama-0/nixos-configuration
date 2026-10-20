import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// The three ways a panel goes away, driven from outside with LASERBAR_EXEC.
//
// None of these can be asserted from a static render: they are things the
// user does TO the shell. Run the fixture three times, once per trigger, and
// probe the sheet interior - it must read as bare ground afterwards.
//
//   LASERBAR_EXEC='wtype -k Escape' \
//     scripts/laserbar-preview.sh tests/laserbar/panel-dismiss.qml /tmp/esc.png 0.62
//
//   LASERBAR_EXEC='swaymsg workspace 2' \
//     scripts/laserbar-preview.sh tests/laserbar/panel-dismiss.qml /tmp/ws.png 0.62
//
//   LASERBAR_EXEC='swaymsg seat - cursor set 120 120; swaymsg seat - cursor press button1; swaymsg seat - cursor release button1' \
//     scripts/laserbar-preview.sh tests/laserbar/panel-dismiss.qml /tmp/click.png 0.62
//
// Probe: the sheet interior at 700,600 is glass while open and bare ground
// once dismissed. 120,120 is far outside the sheet, which spans 490..1430.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
    }

    ControlPanel {
        id: cp

        Component.onCompleted: cp.summon()
    }
}
