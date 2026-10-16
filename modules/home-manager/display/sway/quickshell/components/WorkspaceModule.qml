import QtQuick
import "." as Components

// The workspace strip: one capsule divided into cells, one cell per workspace
// that has windows, icon above and number below. The focused cell is wider and
// takes the accent colour.
//
// The workspace list is a property rather than a direct Quickshell.I3 read, so
// the strip renders a list and something else decides where the list comes
// from (LaserBar.qml wires the live one). Each entry is
// { number, focused, icon }.
Components.RevealMask {
    id: root

    property var workspaces: []
    property color accent: "@capsuleInk@"

    // Read by BarSlots, which does the placing. See BarSlots.qml.
    property string slotSide: "left"
    property int slotOrder: 0
    property bool slotWired: false
    property bool active: false

    readonly property real cellHeight: 38
    readonly property real cellWidthPlain: 27
    readonly property real cellWidthFocused: 37

    // Two-digit workspaces need the extra room or the number touches the
    // dividers either side of it.
    function cellWidth(ws) {
        return (ws.focused ? cellWidthFocused : cellWidthPlain) + (ws.number > 9 ? 6 : 0);
    }

    function cellOffset(index) {
        let x = 0;
        for (let i = 0; i < index && i < workspaces.length; i++) x += cellWidth(workspaces[i]);
        return x;
    }

    readonly property real bodyW: cellOffset(workspaces.length)

    // The span the capsule occupies in panel coordinates, flares included, for
    // BeamSide.pinchSpans. Empty while there is nothing to show, so the beam
    // runs uninterrupted.
    readonly property var occupiedSpan:
        workspaces.length > 0 ? [x, x + width] : []

    width: shell.width
    height: shell.height
    // A capsule with no cells would be a zero-width body whose two flares meet
    // in a black dart. Nothing to show means nothing drawn.
    visible: workspaces.length > 0

    Components.BarShell {
        id: shell
        bodyWidth: Math.max(1, root.bodyW)
        bodyHeight: root.cellHeight
        accentColor: root.accent
        // The focused cell's wash, in body coordinates offset by the flare.
        // Running it to the item's edge when the cell is first or last is what
        // carries the colour out into the flare and tapers it to the point.
        accentFromX: {
            for (let i = 0; i < root.workspaces.length; i++) {
                if (!root.workspaces[i].focused) continue;
                return i === 0 ? 0 : root.flareOffset + root.cellOffset(i);
            }
            return 0;
        }
        accentToX: {
            for (let i = 0; i < root.workspaces.length; i++) {
                if (!root.workspaces[i].focused) continue;
                if (i === root.workspaces.length - 1) return shell.width;
                return root.flareOffset + root.cellOffset(i) + root.cellWidth(root.workspaces[i]);
            }
            return 0;
        }

        // Cells. Explicit x arithmetic, not a Row: the widths animate, and a
        // positioner over a model that is reassigned on every sway event is
        // the failure StatusPanel.qml documents.
        Repeater {
            model: root.workspaces

            Item {
                id: cell
                required property var modelData
                required property int index

                readonly property real cw: root.cellWidth(modelData)

                x: shell.bodyX + root.cellOffset(index)
                y: shell.inset
                width: cw
                height: root.cellHeight
                // A cell growing in from zero has a full-size icon and number
                // from its first frame; without this they spill over its
                // neighbours.
                clip: true

                Components.WorkspaceIcon {
                    name: cell.modelData.icon !== undefined ? cell.modelData.icon : "plain"
                    color: "@capsuleInk@"
                    x: (cell.cw - width) / 2
                    y: 3
                }

                Text {
                    // Sway allows named workspaces, where there is no number
                    // to show. Blank rather than printing the -1 sway reports.
                    text: cell.modelData.number > 0 ? String(cell.modelData.number) : ""
                    color: "@capsuleInk@"
                    font.family: "Orbitron"
                    font.pixelSize: 12
                    font.weight: cell.modelData.focused ? Font.Bold : Font.DemiBold
                    x: (cell.cw - width) / 2
                    y: 21
                }
            }
        }

        // Dividers are siblings of the cells, not children: a cell clips its
        // own content (so a growing cell's icon cannot spill over its
        // neighbour), which would cut a divider straddling the boundary down
        // to half its width.
        Repeater {
            model: Math.max(0, root.workspaces.length - 1)

            Rectangle {
                required property int index

                x: shell.bodyX + root.cellOffset(index + 1) - root.dividerWidth / 2
                y: shell.inset
                width: root.dividerWidth
                height: root.cellHeight
                color: "@capsuleInk@"
            }
        }
    }

    readonly property real flareOffset: shell.flare
    readonly property real dividerWidth: shell.outline * 0.78
}
