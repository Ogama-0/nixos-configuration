import QtQuick
import "." as Components

// One capsule on the bar, holding one or more widgets side by side.
//
// The bar has three groups - left, centre and right - and a widget says
// which group it is in and where in that group it sits:
//
//     BarGroup {
//         slotSide: "centre"
//
//         DndWidget   { pos: 1 }
//         ClockWidget { pos: 2 }
//     }
//
// gives a DND button to the left of the clock, in the middle capsule.
//
// To add a widget: write Foo.qml as a plain Item that sizes itself (set
// `implicitWidth`, or bind `width`), drop it in a group with a `pos`, and
// add the file to `treeFor` in quickshell/default.nix. The group lays it
// out, separates it from its neighbours, and sizes the capsule around it.
// A widget does not deal with the capsule, the beam, or the reveal at all.
//
// The group's own item is a fixed reservation with the capsule centred in
// it, because this is wrapped in a RevealMask whose layer texture is the
// item's size: an item that resized while a widget animated would
// reallocate and re-render that texture every frame. Centring also means
// the capsule opens out to both sides as it grows.
Components.RevealMask {
    id: root

    // --- The slot contract. BarSlots reads these. ---
    property string slotSide: "centre"
    property int slotOrder: 0
    property bool slotWired: false
    property bool active: false

    // --- Bound by BarSlots. A group should not set these itself. ---
    property color strokeColor: "@capsuleInk@"
    property color wireColor: "@capsuleInk@"
    property color wireColorAfterSeam: "@capsuleInk@"
    property real seamX: -1
    property color railColor: "@capsuleInk@"

    property real uiScale: 1
    property real bodyHeight: 38 * uiScale
    // Width the item reserves. The capsule is centred in it and may be any
    // width up to this. Defaults to "whatever the widgets need right now",
    // which is right for a group whose widgets do not change size.
    property real reservedBodyWidth: contentWidth

    // --- Separators, drawn by the group between its widgets and at the
    //     capsule's two ends. A widget draws its own internal divisions. ---
    readonly property real dividerWidth: shell.outline * 0.5
    readonly property real dividerInset: 5 * uiScale
    // The end ones sit where the lip is already narrowing, so a full-length
    // bar there crowds the curve.
    readonly property real endDividerInset: 10 * uiScale

    // Bumped whenever the widget layout changes, so bindings that read it
    // re-evaluate. Child widths are plain properties, not a model.
    property int layoutRevision: 0
    property var widgetOffsets: []
    readonly property real contentWidth:
        widgetOffsets.length > 0 ? widgetOffsets[widgetOffsets.length - 1] : 0

    readonly property alias shell: shell

    // True when the widgets at the capsule's ends want a separator there.
    property bool endsBounded: false

    width: reservedBodyWidth + 2 * shell.flare + shell.outline
    height: shell.height
    visible: contentWidth > 0

    // What the group actually draws, in the group's OWN coordinates: BarSlots
    // places by this and BeamSide pinches the strands around it, so a group
    // whose reservation is wider than its capsule still sits where it should.
    // BarSlots adds the group's x to get panel coordinates.
    //
    // Group-local, and never `x + shell.x`, because BarSlots connects
    // occupiedSpanChanged to its layout pass and that pass WRITES x. Reading x
    // here closes the loop: placing a module re-emits the signal that placed
    // it, re-entering relayout() midway through its own run. Qt reports it as
    // a binding loop on this property and then stops re-evaluating it, which
    // is worse than the churn - the span freezes holding the x the group had
    // before it moved, so the beam gets pinched over a stretch where there is
    // no longer a capsule and runs straight through the one there is. That is
    // what the music widget used to trigger every time a player quit and the
    // right capsule shrank by the widget's whole width.
    readonly property var occupiedSpan:
        contentWidth > 0 ? [shell.x, shell.x + shell.width] : []

    default property alias content: widgetHost.data

    function widgets() {
        const out = [];
        for (let i = 0; i < widgetHost.children.length; i++) {
            const w = widgetHost.children[i];
            if (w.pos !== undefined) out.push(w);
        }
        return out.sort((a, b) => a.pos - b.pos);
    }

    // Lay the widgets out left to right and record the boundaries between
    // them, which is also where the separators go.
    function layoutWidgets() {
        // A widget with no width is not in the capsule at all - the music
        // widget collapses to nothing with no player. Laying it out anyway
        // would leave a separator at its zero-width boundary, which reads
        // as a stray bar against the capsule's lip.
        const ws = widgets().filter(w => w.width > 0);
        const offsets = [0];
        let x = 0;
        for (const w of ws) {
            w.x = shell.bodyX + x;
            w.y = shell.bodyY;
            w.height = root.bodyHeight;
            x += w.width;
            offsets.push(x);
        }
        widgetOffsets = offsets;
        endsBounded = ws.length > 0
            && ws[0].boundedEnds === true
            && ws[ws.length - 1].boundedEnds === true;
        layoutRevision++;
    }

    function trackWidgets() {
        for (const w of widgets()) {
            if (w.groupWired) continue;
            w.widthChanged.connect(root.layoutWidgets);
            // Guarded, like BarSlots does for groups: a widget that does not
            // want one of these should not break the group.
            if (w.active !== undefined) w.active = Qt.binding(() => root.active);
            if (w.railColor !== undefined) w.railColor = Qt.binding(() => root.railColor);
            if (w.bodyHeight !== undefined) w.bodyHeight = Qt.binding(() => root.bodyHeight);
            if (w.uiScale !== undefined) w.uiScale = Qt.binding(() => root.uiScale);
            w.groupWired = true;
        }
        layoutWidgets();
    }

    // A widget may ask for part of the capsule to be washed in the rail
    // colour - the focused workspace cell. It publishes the span in its own
    // coordinates and the group places it; a span that reaches the widget's
    // own edge, and that widget is at the capsule's edge, runs on into the
    // lip rather than stopping at the body.
    function accentSpan() {
        const ws = widgets().filter(w => w.width > 0);
        for (let i = 0; i < ws.length; i++) {
            const w = ws[i];
            if (w.accentFromX === undefined || w.accentToX === undefined) continue;
            if (w.accentToX <= w.accentFromX) continue;
            const first = i === 0 && w.accentFromX <= 0;
            const last = i === ws.length - 1 && w.accentToX >= w.width;
            return [first ? 0 : w.x + w.accentFromX,
                    last ? shell.width : w.x + w.accentToX];
        }
        return [0, 0];
    }

    onChildrenChanged: Qt.callLater(trackWidgets)
    Component.onCompleted: Qt.callLater(trackWidgets)

    Components.BarShell {
        id: shell

        // Centred in the reservation.
        x: (root.width - width) / 2
        bodyWidth: Math.max(1, Math.min(root.contentWidth, root.reservedBodyWidth))
        bodyHeight: root.bodyHeight
        uiScale: root.uiScale
        strokeColor: root.strokeColor
        wireColor: root.wireColor
        wireColorAfterSeam: root.wireColorAfterSeam
        // seamX arrives in the group's coordinates and the shell reads it in
        // its own; they differ by shell.x.
        seamX: root.seamX < 0 ? -1 : root.seamX - x
        accentColor: root.railColor
        accentFromX: { root.layoutRevision; return root.accentSpan()[0]; }
        accentToX: { root.layoutRevision; return root.accentSpan()[1]; }

        Item {
            id: widgetHost
            anchors.fill: parent
        }

        // One at each boundary between widgets. At the capsule's two ends
        // only if the widget there asks for it (`boundedEnds`): the workspace
        // strip does, because the plate runs out into a lip past its first
        // and last cell and that white otherwise reads as part of them. A
        // single clock does not - it would just be two bars either side of
        // the time.
        Repeater {
            model: root.widgetOffsets.length

            Rectangle {
                required property int index

                readonly property bool isEnd:
                    index === 0 || index === root.widgetOffsets.length - 1
                readonly property real inset:
                    isEnd ? root.endDividerInset : root.dividerInset
                visible: !isEnd || root.endsBounded

                x: shell.bodyX + root.widgetOffsets[index] - root.dividerWidth / 2
                y: shell.bodyY + inset
                width: root.dividerWidth
                height: root.bodyHeight - 2 * inset
                radius: width / 2
                color: "@capsuleInk@"
            }
        }
    }
}
