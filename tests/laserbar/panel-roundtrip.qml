import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Summoned, undocked, then docked again. The chrome must come back
// pixel-identical to a plain summon: anything left over is a resting binding
// that did not stand down while the transition ran, which is what broke
// re-attach once already.
//
// Compare the TAIL REGION, not the whole frame. The panel carries a ticking
// clock and live CPU and RAM, so two renders of it are never identical and a
// whole-frame diff says nothing:
//
//   scripts/laserbar-preview.sh tests/laserbar/panel-roundtrip.qml /tmp/a.png 0.62
//   scripts/laserbar-preview.sh tests/laserbar/panel-open.qml      /tmp/b.png 0.62
//   for f in a b; do magick /tmp/$f.png -crop 420x60+780+990 +repage /tmp/$f-t.png; done
//   magick compare -metric AE -fuzz 2% /tmp/a-t.png /tmp/b-t.png null:
//
// Expect 0. The same crop against panel-detached.qml differs by ~1900, which
// is how you know the comparison can still fail.


//

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
        Component.onCompleted: { cp.summon(); cp.detach(); cp.reattach(); }
    }
}
