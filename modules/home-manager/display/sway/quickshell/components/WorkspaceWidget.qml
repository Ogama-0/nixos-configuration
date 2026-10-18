import QtQuick
import "." as Components

// One cell per workspace that has windows, icon above and number below. The
// focused cell is wider and asks its group to wash it in the rail colour.
//
// The list is a property rather than a direct Quickshell.I3 read, so this
// renders a list and something else decides where the list comes from
// (LaserBar.qml wires the live one). Each entry is { id, number, focused,
// icon }.
Item {
    id: root

    // Read by BarGroup: where this sits inside its group.
    property int pos: 1
    property bool groupWired: false
    // Bound by BarGroup.
    property bool active: false
    property real bodyHeight: 38
    property color railColor: "@capsuleInk@"

    property var workspaces: []

    // The group puts a separator at the capsule's ends for this widget: the
    // plate runs out into a lip past the first and last cell, and without one
    // that white reads as part of those cells, making them look about twice
    // the width of their neighbours.
    readonly property bool boundedEnds: true

    readonly property real cellWidthPlain: 27
    readonly property real cellWidthFocused: 37

    // Focus moves faster than a workspace opening or closing: a switch
    // answers a keypress, a life event changes what exists.
    property int switchDuration: 110
    property int lifeDuration: 130
    // Overrides both when positive. For slowing a transition down to look at
    // it, which is also how the render test catches a cell mid-growth.
    property int transitionDuration: 0

    property real maxCells: 10
    // What the group should reserve, so its item never resizes mid-animation.
    readonly property real reservedWidth:
        maxCells * (cellWidthPlain + 6) + (cellWidthFocused - cellWidthPlain)

    // Identity and display live in the model; the widths live in plain
    // arrays beside it, indexed by row. Reading roles sixty times a second
    // to lay the cells out would undo the point of using a model at all.
    ListModel { id: cellModel }
    property var fromW: []
    property var toW: []
    property real phase: 1
    // Bumped on every model change: ListModel.get() does not register a
    // binding dependency, so bindings that read rows need something that
    // does.
    property int revision: 0

    readonly property real dividerWidth: 2.3
    readonly property real dividerInset: 5

    function cellWidth(focused, number) {
        return (focused ? cellWidthFocused : cellWidthPlain) + (number > 9 ? 6 : 0);
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
        for (let i = 0; i < index && i < cellModel.count; i++) x += widthAt(i);
        return x;
    }

    width: cellOffset(cellModel.count)
    implicitWidth: width

    // Where the focused cell is, in this widget's own coordinates. BarGroup
    // places the wash and lets it run into the lip when it reaches an edge.
    readonly property real accentFromX: {
        root.revision;
        for (let i = 0; i < cellModel.count; i++) {
            if (!cellModel.get(i).focused) continue;
            return i === 0 ? 0 : cellOffset(i);
        }
        return 0;
    }
    readonly property real accentToX: {
        root.revision;
        for (let i = 0; i < cellModel.count; i++) {
            if (!cellModel.get(i).focused) continue;
            return i === cellModel.count - 1 ? width : cellOffset(i) + widthAt(i);
        }
        return 0;
    }

    onWorkspacesChanged: sync()
    Component.onCompleted: sync()

    // True when we are already showing, or already animating towards, exactly
    // this list. LaserBar.qml rebuilds its array on every i3 event, including
    // ones that change nothing here, and restarting the transition each time
    // is pointless work.
    function alreadyHeadedFor(incoming) {
        const live = [];
        for (let i = 0; i < cellModel.count; i++) {
            const r = cellModel.get(i);
            if (!r.dying) live.push(r);
        }
        if (live.length !== incoming.length) return false;
        for (let i = 0; i < live.length; i++) {
            if (live[i].wsId !== incoming[i].id) return false;
            if (live[i].focused !== incoming[i].focused) return false;
            if (live[i].icon !== incoming[i].icon) return false;
        }
        return true;
    }

    // Bring the model to `next` by moving, inserting and updating rows rather
    // than replacing it. A replaced model destroys and rebuilds every
    // delegate - and each cell delegate carries an icon made of four
    // CurveRenderer paths - so a bare focus change used to tear down the
    // whole strip and build it again.
    function reconcile(next) {
        for (let i = 0; i < next.length; i++) {
            const want = next[i];
            let at = -1;
            for (let j = i; j < cellModel.count; j++) {
                if (cellModel.get(j).wsId === want.wsId) { at = j; break; }
            }
            if (at === -1) {
                cellModel.insert(i, want);
                continue;
            }
            if (at !== i) cellModel.move(at, i, 1);
            const cur = cellModel.get(i);
            if (cur.focused !== want.focused) cellModel.setProperty(i, "focused", want.focused);
            if (cur.icon !== want.icon) cellModel.setProperty(i, "icon", want.icon);
            if (cur.number !== want.number) cellModel.setProperty(i, "number", want.number);
            if (cur.dying !== want.dying) cellModel.setProperty(i, "dying", want.dying);
        }
        while (cellModel.count > next.length) cellModel.remove(next.length);
        revision++;
    }

    // Merge the incoming list into the displayed one: survivors keep their
    // place, newcomers start at zero width, and anything gone is kept as a
    // dying row so it shrinks out instead of vanishing.
    function sync() {
        const incoming = workspaces || [];
        if (alreadyHeadedFor(incoming)) return;

        const held = [];
        for (let i = 0; i < cellModel.count; i++) held.push(widthAt(i));

        const present = {};
        for (let i = 0; i < incoming.length; i++) present[incoming[i].id] = true;

        const next = [];
        for (let i = 0; i < incoming.length; i++) {
            const w = incoming[i];
            next.push({ wsId: w.id, number: w.number, focused: w.focused,
                        icon: w.icon === undefined ? "plain" : w.icon, dying: false });
        }

        let membershipChanged = false;
        const heldById = {};
        for (let i = 0; i < cellModel.count; i++) {
            const r = cellModel.get(i);
            heldById[r.wsId] = held[i];
            if (r.dying || present[r.wsId]) continue;
            membershipChanged = true;
            next.splice(Math.min(i, next.length), 0,
                        { wsId: r.wsId, number: r.number, focused: false,
                          icon: r.icon, dying: true });
        }

        const nf = [];
        const nt = [];
        for (let i = 0; i < next.length; i++) {
            const c = next[i];
            const had = heldById[c.wsId];
            if (had === undefined) membershipChanged = true;
            nf.push(had === undefined ? 0 : had);
            nt.push(c.dying ? 0 : cellWidth(c.focused, c.number));
        }

        reconcile(next);
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

    // Drop the rows that have finished shrinking and rebase the widths, so
    // the next transition starts from where this one ended.
    function settle() {
        const w = [];
        for (let i = cellModel.count - 1; i >= 0; i--) {
            if (cellModel.get(i).dying) cellModel.remove(i);
        }
        for (let i = 0; i < cellModel.count; i++) w.push(toW[i]);
        fromW = w;
        toW = w;
        phase = 1;
        revision++;
    }

    // Cells. Explicit x arithmetic, not a Row: the widths animate, and a
    // positioner over a model reassigned on every sway event is the failure
    // StatusPanel.qml documents.
    Repeater {
        model: cellModel

        Item {
            id: cell

            required property int index
            required property int number
            required property bool focused
            required property string icon

            readonly property real cw: root.widthAt(index)

            x: root.cellOffset(index)
            y: 0
            width: cw
            height: root.bodyHeight
            // A cell growing in from zero has a full-size icon and number
            // from its first frame; without this they spill over its
            // neighbours.
            clip: true
            // Fades up over the first few pixels of growth, so a cell opens
            // rather than pops.
            opacity: Math.min(1, cw / root.cellWidthPlain)

            Components.WorkspaceIcon {
                name: cell.icon
                color: "@capsuleInk@"
                x: (cell.cw - width) / 2
                y: 3
            }

            Text {
                // Sway allows named workspaces, where there is no number to
                // show. Blank rather than printing the -1 sway reports.
                text: cell.number > 0 ? String(cell.number) : ""
                color: "@capsuleInk@"
                font.family: "Orbitron"
                font.pixelSize: 12
                font.weight: cell.focused ? Font.Bold : Font.DemiBold
                x: (cell.cw - width) / 2
                y: 21
            }
        }
    }

    // Between cells only. The separators at this widget's own two ends
    // belong to the group, which also puts them between neighbouring
    // widgets.
    Repeater {
        model: Math.max(0, cellModel.count - 1)

        Rectangle {
            required property int index

            x: root.cellOffset(index + 1) - root.dividerWidth / 2
            y: root.dividerInset
            width: root.dividerWidth
            height: root.bodyHeight - 2 * root.dividerInset
            radius: width / 2
            // A divider whose cell has shrunk to nothing would otherwise sit
            // on top of its neighbour's edge.
            opacity: Math.min(1, root.widthAt(index) / root.cellWidthPlain)
            color: "@capsuleInk@"
        }
    }
}
