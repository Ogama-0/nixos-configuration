import QtQuick
import Quickshell
import "components"

// Minimal: the panel and nothing else. If a click dismisses it here but not
// in panel-dismiss.qml, the fixture's own backdrop window is implicated.
Scope {
    ControlPanel { id: cp; Component.onCompleted: cp.summon() }
}
