import QtQuick

// Places bar modules along the beam and wires each one's reveal, so a module
// declares where it belongs and nothing else:
//
//     BarSlots {
//         ClockModule { slotSide: "centre" }
//         WifiModule  { slotSide: "right" }
//     }
//
// A module needs `slotSide` ("left" | "centre" | "right") and may set
// `slotOrder`; anything without a slotSide is left alone.
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

    property real edgeMargin: 24
    property real spacing: 16

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

    function relayout() {
        if (panelWidth <= 0) return;

        let x = edgeMargin;
        for (const c of onSide("left")) {
            c.x = x;
            x += c.width + spacing;
        }

        x = panelWidth - edgeMargin;
        for (const c of onSide("right")) {
            x -= c.width;
            c.x = x;
            x -= spacing;
        }

        const centre = onSide("centre");
        let total = 0;
        for (const c of centre) total += c.width;
        if (centre.length > 1) total += spacing * (centre.length - 1);
        x = (panelWidth - total) / 2;
        for (const c of centre) {
            c.x = x;
            x += c.width + spacing;
        }

        for (const c of slotted()) c.y = beamY - c.height / 2;
    }

    // Reveal wiring, bound once per module so it keeps tracking the beams.
    // Qt.binding, not assignment: a plain assignment would freeze each module
    // at whatever the beams happened to be doing when it was placed.
    function wire() {
        for (const c of slotted()) {
            c.coverLeft = Qt.binding(() => root.coverLeft);
            c.coverRight = Qt.binding(() => root.coverRight);
            c.panelWidth = Qt.binding(() => root.panelWidth);
            if (c.active !== undefined) c.active = Qt.binding(() => root.active);

            // A module that changes width - the workspace strip, while a cell
            // grows - moves everything after it on its side and recentres the
            // centre slot. Connected once; `slotWired` guards against wiring
            // the same child twice when children change again later.
            if (!c.slotWired) {
                c.widthChanged.connect(root.relayout);
                c.slotWired = true;
            }
        }
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
