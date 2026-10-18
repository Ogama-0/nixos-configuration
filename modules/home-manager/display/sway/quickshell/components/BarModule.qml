import QtQuick
import "." as Components

// Base type for every laser-bar module.
//
// Adding a module is three steps and no more:
//
//   1. Write Foo.qml with BarModule as its root. Set `bodyWidth` and put the
//      plate's content inside it. That content is positioned against the
//      shell, so `shell.bodyX` / `shell.bodyY` are the plate's origin.
//   2. Add one line to the BarSlots block in LaserBar.qml, saying which side
//      it belongs on.
//   3. Add one line to `treeFor` in quickshell/default.nix, or the file will
//      not exist at runtime.
//
// Everything else is handled here: the capsule, the reveal mask that keeps
// the module in step with the beam, the rail colours, and the collision seam.
// A module never sets those, and BarSlots binds them all - so a module that
// forgets one cannot break the bar.
Components.RevealMask {
    id: root

    // --- The slot contract. BarSlots reads these. ---
    property string slotSide: "centre"
    property int slotOrder: 0
    // Set by BarSlots once it has wired this module up.
    property bool slotWired: false
    property bool active: false

    // --- Bound by BarSlots. A module should not set these itself. ---
    property color strokeColor: "@capsuleInk@"
    property color wireColor: "@capsuleInk@"
    property color wireColorAfterSeam: "@capsuleInk@"
    property real seamX: -1
    // The colour of the rail covering this module, for anything inside it
    // that should follow the battery (the focused workspace cell).
    property color railColor: "@capsuleInk@"

    // --- What a module chooses. ---
    property real bodyWidth: 100
    property real bodyHeight: 38
    // Offset of the capsule inside the item, for a module whose box is bigger
    // than what it draws (the workspace strip reserves room for ten cells).
    property real shellX: 0

    property alias accentColor: shell.accentColor
    property alias accentFromX: shell.accentFromX
    property alias accentToX: shell.accentToX
    readonly property alias shell: shell

    // What the module actually draws, in panel coordinates. BarSlots places
    // by this and hands it to BeamSide for the strand pinch, so a module with
    // a box wider than its capsule still sits where it should and the beam
    // only flattens where something is really in the way.
    readonly property var occupiedSpan: [x + shell.x, x + shell.x + shell.width]

    width: shell.width
    height: shell.height

    default property alias content: shell.content

    Components.BarShell {
        id: shell

        x: root.shellX
        bodyWidth: root.bodyWidth
        bodyHeight: root.bodyHeight
        strokeColor: root.strokeColor
        wireColor: root.wireColor
        wireColorAfterSeam: root.wireColorAfterSeam
        // seamX arrives in the module's coordinates; the shell reads it in
        // its own, and the two differ by shell.x.
        seamX: root.seamX < 0 ? -1 : root.seamX - x
    }
}
