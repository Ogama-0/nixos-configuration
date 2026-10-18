import QtQuick

// Places bar modules along the beam and wires every input they take, so a
// module declares where it belongs and nothing else:
//
//     BarSlots {
//         ClockModule { slotSide: "centre" }
//         WifiModule  { slotSide: "right" }
//     }
//
// A module needs `slotSide` ("left" | "centre" | "right") and may set
// `slotOrder`; anything without a slotSide is left alone. See BarModule.qml,
// which every module should be built on.
//
// `slotOrder` counts outward from the module's own edge: on the left and in
// the centre the lowest order is leftmost, but on the right the lowest order
// is RIGHTMOST, because that side is laid out inward from the right margin.
//
// This item must fill the panel at x 0. RevealMask reads its own `x` as
// panel-local (see RevealMask.qml), and a child's x here is panel-local only
// because this container starts at the panel's own origin - put it anywhere
// else and every module's reveal would be offset by that much.
//
// Positions are assigned imperatively rather than by a Row or positioner.
// Two reasons: a module's width changes while it animates, and the repo has
// already been bitten once by a positioner silently failing to re-lay-out
// (see the comment in StatusPanel.qml).
Item {
    id: root

    required property real panelWidth
    required property real beamY
    required property real coverLeft
    required property real coverRight
    required property bool active
    property real uiScale: 1

    // The two rails and where they meet, so modules can be coloured from one
    // place rather than each repeating the same conditional.
    property color leftRail: "#FFFFFF"
    property color rightRail: "#FFFFFF"
    property color ink: "#FF000000"
    property real meetX: 0

    // Far enough in that there is real beam before the first module. The
    // strand pinch reaches 20px either side of a module, so a 24px margin
    // left nothing but ramp between the screen edge and the capsule - the bar
    // began as a flat line rather than a wave.
    property real edgeMargin: 90 * uiScale
    property real spacing: 16 * uiScale

    // Where the placed modules actually draw, in panel coordinates, for
    // BeamSide.pinchSpans. Recomputed with the layout, since a module that
    // changes width moves the spans of everything after it.
    property var moduleSpans: []

    anchors.fill: parent

    function slotted() {
        const out = [];
        for (let i = 0; i < children.length; i++) {
            const c = children[i];
            if (c.slotSide !== undefined && c.slotSide !== "") out.push(c);
        }
        return out;
    }

    function onSide(side) {
        return slotted()
            .filter(c => c.slotSide === side)
            .sort((a, b) => (a.slotOrder || 0) - (b.slotOrder || 0));
    }

    // A module's box can be wider than what it draws, so lay out by the drawn
    // span and keep the gaps between modules visually even.
    function drawnLead(c) {
        const s = c.occupiedSpan;
        return (s && s.length === 2) ? s[0] - c.x : 0;
    }
    function drawnWidth(c) {
        const s = c.occupiedSpan;
        return (s && s.length === 2) ? s[1] - s[0] : c.width;
    }
    // Assigning an unchanged value still costs a binding re-evaluation, and
    // occupiedSpan is wired back to relayout - so only move what moved.
    function place(c, x) {
        if (Math.abs(c.x - x) > 0.01) c.x = x;
    }

    function relayout() {
        if (panelWidth <= 0) return;

        let x = edgeMargin;
        for (const c of onSide("left")) {
            place(c, x - drawnLead(c));
            x += drawnWidth(c) + spacing;
        }

        x = panelWidth - edgeMargin;
        for (const c of onSide("right")) {
            x -= drawnWidth(c);
            place(c, x - drawnLead(c));
            x -= spacing;
        }

        const centre = onSide("centre");
        let total = 0;
        for (const c of centre) total += drawnWidth(c);
        if (centre.length > 1) total += spacing * (centre.length - 1);
        x = (panelWidth - total) / 2;
        for (const c of centre) {
            place(c, x - drawnLead(c));
            x += drawnWidth(c) + spacing;
        }

        for (const c of slotted()) {
            const y = beamY - c.height / 2;
            if (Math.abs(c.y - y) > 0.01) c.y = y;
        }

        const spans = [];
        for (const c of slotted()) {
            if (!c.visible || c.width <= 0) continue;
            const s = c.occupiedSpan;
            spans.push((s && s.length === 2) ? s : [c.x, c.x + c.width]);
        }
        moduleSpans = spans;
    }

    // Every input a module takes is bound here, guarded. Unguarded writes
    // would throw on the first module that does not declare one of them, and
    // that exception escapes wire() - so one incomplete module used to leave
    // EVERY module unplaced at x 0 rather than just breaking itself.
    function bind(c, name, fn) {
        if (c[name] === undefined) return;
        c[name] = Qt.binding(fn);
    }

    function wireOne(c) {
        bind(c, "coverLeft", () => root.coverLeft);
        bind(c, "coverRight", () => root.coverRight);
        bind(c, "panelWidth", () => root.panelWidth);
        bind(c, "active", () => root.active);
        bind(c, "uiScale", () => root.uiScale);
        bind(c, "strokeColor", () => root.ink);
        bind(c, "railColor", () => c.x < root.meetX ? root.leftRail : root.rightRail);
        // Lightened: a filament the exact colour of the rail disappears where
        // the module's lip crosses the beam.
        bind(c, "wireColor", () => Qt.lighter(c.x < root.meetX ? root.leftRail : root.rightRail, 1.5));
        bind(c, "wireColorAfterSeam", () => Qt.lighter(root.rightRail, 1.5));
        // Where the beams meet, if that lands inside this module.
        bind(c, "seamX", () => {
            const local = root.meetX - c.x;
            return (local >= 0 && local <= c.width) ? local : -1;
        });

        if (!c.slotWired) {
            c.widthChanged.connect(root.relayout);
            // Width alone is not enough. A module whose item size is fixed
            // but whose drawn capsule grows - the workspace strip, which
            // reserves room for ten cells - never changes width, so its span
            // would keep whatever value it had when the bar started and the
            // beam would run straight through the capsule.
            if (c.occupiedSpanChanged !== undefined)
                c.occupiedSpanChanged.connect(root.relayout);
            if (c.visibleChanged !== undefined)
                c.visibleChanged.connect(root.relayout);
            c.slotWired = true;
        }
    }

    function wire() {
        for (const c of slotted()) wireOne(c);
    }

    // Deferred, never immediate. childrenChanged fires while the children are
    // still being constructed, and touching a half-built child from there -
    // assigning it a binding, connecting to its signals - can abort the whole
    // tree's creation, which shows up as a panel that simply never draws and
    // no error on stdout.
    function settle() {
        wire();
        relayout();
    }

    onPanelWidthChanged: Qt.callLater(relayout)
    onBeamYChanged: Qt.callLater(relayout)
    onChildrenChanged: Qt.callLater(settle)
    Component.onCompleted: Qt.callLater(settle)
}
