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
//
// The item's own size is FIXED, at the width ten workspaces would need, with
// the capsule centred inside it. Two reasons: this is wrapped in a RevealMask,
// whose layer texture is exactly the item's size, so an item that resized
// while a cell grew would reallocate and re-render that texture every
// animation frame - the resizing-layer cost this design exists to avoid. And a
// capsule centred in a fixed box opens out to both sides as it grows, which is
// the behaviour asked for.
Components.RevealMask {
    id: root

    property var workspaces: []
    property color accent: "@capsuleInk@"

    // Read by BarSlots, which does the placing. See BarSlots.qml.
    property string slotSide: "left"
    property int slotOrder: 0
    property bool slotWired: false
    property bool active: false

    // A dark tint of the rail covering this module, so the outline reads as
    // the beam continuing through it rather than as a black box laid on top.
    property color strokeColor: "@capsuleInk@"
    // Item-local x of the beams' meeting point when it lands inside this
    // module, or -1. See BarShell.
    property real seamX: -1
    property color wireColor: "@capsuleInk@"
    property color wireColorAfterSeam: "@capsuleInk@"

    readonly property real cellHeight: 38
    readonly property real cellWidthPlain: 27
    readonly property real cellWidthFocused: 37

    // Focus moves faster than a workspace opening or closing: a switch answers
    // a keypress, a life event changes what exists.
    property int switchDuration: 110
    property int lifeDuration: 130
    // Overrides both when positive. For slowing a transition down to look at
    // it, which is also how the render test catches a cell mid-growth.
    property int transitionDuration: 0

    property real maxCells: 10
    readonly property real maxBodyWidth:
        maxCells * (cellWidthPlain + 6) + (cellWidthFocused - cellWidthPlain)

    // Displayed cells, which is not the same list as `workspaces`: a cell
    // whose workspace has closed stays here, marked dying, until it has
    // finished shrinking away.
    property var cells: []
    property var fromW: []
    property var toW: []
    property real phase: 1

    function cellWidth(ws) {
        return (ws.focused ? cellWidthFocused : cellWidthPlain) + (ws.number > 9 ? 6 : 0);
    }

    // One interpolated phase drives every cell, so they move in lockstep and
    // the offsets stay exact at any point in the transition.
    function widthAt(i) {
        const a = fromW.length > i ? fromW[i] : 0;
        const b = toW.length > i ? toW[i] : 0;
        return a + (b - a) * phase;
    }

    function cellOffset(index) {
        let x = 0;
        for (let i = 0; i < index && i < cells.length; i++) x += widthAt(i);
        return x;
    }

    readonly property real bodyW: cellOffset(cells.length)
    readonly property real dividerWidth: shell.outline * 0.5
    // Dividers stop short of the outer wire rather than running into it: a
    // separator that touches the border reads as part of the frame.
    readonly property real dividerInset: 5
    // The two at the plate's ends are shorter still: they sit where the lip
    // is already narrowing, so a full-length bar there crowds the curve.
    readonly property real endDividerInset: 10

    width: maxBodyWidth + 2 * shell.flare + shell.outline
    height: shell.height
    // A capsule with no cells would be a zero-width body whose two flares meet
    // in a black dart. Nothing to show means nothing drawn.
    visible: cells.length > 0

    // Where the capsule actually sits, in panel coordinates, for
    // BeamSide.pinchSpans. The item's own box is the ten-workspace
    // reservation, and pinching on that would flatten the strands over empty
    // beam.
    readonly property var occupiedSpan:
        cells.length > 0 ? [x + shell.x, x + shell.x + shell.width] : []

    onWorkspacesChanged: sync()
    Component.onCompleted: sync()

    // Merge the incoming list into the displayed one: survivors keep their
    // place, newcomers start at zero width, and anything gone is kept as a
    // dying cell so it shrinks out instead of vanishing.
    // True when we are already showing, or already animating towards, exactly
    // this list. LaserBar.qml rebuilds its array on every i3 event, including
    // ones that change nothing here, and restarting the transition each time
    // would leave the strip permanently mid-animation.
    function alreadyHeadedFor(incoming) {
        const target = [];
        for (let i = 0; i < cells.length; i++) {
            if (!cells[i].dying) target.push(cells[i]);
        }
        if (target.length !== incoming.length) return false;
        for (let i = 0; i < target.length; i++) {
            if (target[i].number !== incoming[i].number) return false;
            if (target[i].focused !== incoming[i].focused) return false;
            if (target[i].icon !== incoming[i].icon) return false;
        }
        return true;
    }

    function sync() {
        const incoming = workspaces || [];
        if (alreadyHeadedFor(incoming)) return;
        const held = [];
        for (let i = 0; i < cells.length; i++) held.push(widthAt(i));

        const present = {};
        for (let i = 0; i < incoming.length; i++) present[incoming[i].number] = true;

        const next = [];
        for (let i = 0; i < incoming.length; i++) {
            const w = incoming[i];
            next.push({ number: w.number, focused: w.focused, icon: w.icon, dying: false });
        }

        let membershipChanged = false;
        for (let i = 0; i < cells.length; i++) {
            const c = cells[i];
            if (c.dying || present[c.number]) continue;
            membershipChanged = true;
            next.splice(Math.min(i, next.length), 0,
                        { number: c.number, focused: false, icon: c.icon, dying: true });
        }

        const heldByNumber = {};
        for (let i = 0; i < cells.length; i++) heldByNumber[cells[i].number] = held[i];

        const nf = [];
        const nt = [];
        for (let i = 0; i < next.length; i++) {
            const c = next[i];
            const had = heldByNumber[c.number];
            if (had === undefined) membershipChanged = true;
            nf.push(had === undefined ? 0 : had);
            nt.push(c.dying ? 0 : cellWidth(c));
        }

        cells = next;
        fromW = nf;
        toW = nt;

        phaseAnim.stop();
        phase = 0;
        phaseAnim.duration = transitionDuration > 0
            ? transitionDuration
            : (membershipChanged ? lifeDuration : switchDuration);
        phaseAnim.start();
    }

    NumberAnimation {
        id: phaseAnim
        target: root
        property: "phase"
        from: 0
        to: 1
        duration: root.switchDuration
        easing.type: Easing.OutCubic
        onFinished: root.settle()
    }

    // Drop the cells that have finished shrinking and rebase the widths, so
    // the next transition starts from where this one ended.
    function settle() {
        const kept = [];
        const w = [];
        for (let i = 0; i < cells.length; i++) {
            if (cells[i].dying) continue;
            kept.push(cells[i]);
            w.push(toW[i]);
        }
        cells = kept;
        fromW = w;
        toW = w;
        phase = 1;
    }

    Components.BarShell {
        id: shell

        x: (root.width - width) / 2
        bodyWidth: Math.max(1, root.bodyW)
        bodyHeight: root.cellHeight
        accentColor: root.accent
        strokeColor: root.strokeColor
        wireColor: root.wireColor
        wireColorAfterSeam: root.wireColorAfterSeam
        seamX: root.seamX

        // The focused cell's wash. Running it to the item's edge when the cell
        // is first or last carries the colour out into the flare and tapers it
        // to the point.
        accentFromX: {
            for (let i = 0; i < root.cells.length; i++) {
                if (!root.cells[i].focused) continue;
                return i === 0 ? 0 : shell.bodyX + root.cellOffset(i);
            }
            return 0;
        }
        accentToX: {
            for (let i = 0; i < root.cells.length; i++) {
                if (!root.cells[i].focused) continue;
                if (i === root.cells.length - 1) return shell.width;
                return shell.bodyX + root.cellOffset(i) + root.widthAt(i);
            }
            return 0;
        }

        // Cells. Explicit x arithmetic, not a Row: the widths animate, and a
        // positioner over a model reassigned on every sway event is the
        // failure StatusPanel.qml documents.
        Repeater {
            model: root.cells

            Item {
                id: cell
                required property var modelData
                required property int index

                readonly property real cw: root.widthAt(index)

                x: shell.bodyX + root.cellOffset(index)
                y: shell.bodyY
                width: cw
                height: root.cellHeight
                // A cell growing in from zero has a full-size icon and number
                // from its first frame; without this they spill over its
                // neighbours.
                clip: true
                // Fades up over the first few pixels of growth, so a cell
                // opens rather than pops.
                opacity: Math.min(1, cw / root.cellWidthPlain)

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
        // own content, which would cut a divider straddling the boundary down
        // to half its width.
        //
        // One at each end too, not just between cells. The plate runs out
        // into a lip past the first and last cell, and without a divider that
        // white is read as part of those cells - which makes them look around
        // twice the width of their neighbours.
        Repeater {
            model: root.cells.length > 0 ? root.cells.length + 1 : 0

            Rectangle {
                required property int index

                readonly property real inset:
                    (index === 0 || index === root.cells.length)
                        ? root.endDividerInset : root.dividerInset

                x: shell.bodyX + root.cellOffset(index) - root.dividerWidth / 2
                y: shell.bodyY + inset
                width: root.dividerWidth
                height: root.cellHeight - 2 * inset
                radius: width / 2
                // A divider whose cell has shrunk to nothing would otherwise
                // sit on top of its neighbour's edge. The end ones are always
                // present.
                opacity: (index === 0 || index === root.cells.length) ? 1
                       : Math.min(1, root.widthAt(index) / root.cellWidthPlain)
                color: "@capsuleInk@"
            }
        }
    }
}
