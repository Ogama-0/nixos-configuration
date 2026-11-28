import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

// What a notification looks like when it arrives, as opposed to when you go
// looking for it. Same plate, same wire, same NotificationRow as the centre -
// a toast that looks different from its own entry in the list is two designs
// for one thing.
//
// Its own layer surface, top right, taking the pointer only where a toast
// actually is so the rest of the screen stays clickable.
//
// The arrival is where this thing spends its character. A toast flies in from
// off-screen right and overshoots slightly, and its wire is DRAWN down the
// side as it lands - the bar's own beam, doing the one gesture the bar does.
// Everything else stays quiet so that reads.
PanelWindow {
    id: root

    property real uiScale: 1
    property int maxShown: 3
    readonly property real toastWidth: 340

    // The clock behind every "5m ago". Owned by ControlPanel and handed down,
    // so the toasts and the centre cannot disagree about what time it is.
    property var clock: null

    // ---- the speed budget ----
    //
    // Every duration in this file, in one block. Arrival used to be 320ms of
    // OutBack over 368px of travel with a 1.5 overshoot, and the whole thing
    // read as the shell being slow to react - it was not, the pipeline from
    // notify-send to here measures well under 100ms, it was just a long
    // entrance. Travel distance mattered as much as duration: a plate
    // crossing a third of the screen looks slow however fast it is moving.
    readonly property int flyMs: 170
    readonly property real flyOvershoot: 1.1
    readonly property real flyTravel: 120 * uiScale
    readonly property int fadeMs: 90
    readonly property int wireDelayMs: 40
    readonly property int wireDrawMs: 130
    readonly property int exitMs: 110
    readonly property int moveMs: 100
    readonly property int expandMs: 140

    readonly property int lifeMs: 6000
    // Low urgency is a scan finishing, not a person. Off the screen sooner.
    readonly property int lifeLowMs: 3500
    // How many a packed toast remembers. Past this the count still rises;
    // what you lose is being able to open them here rather than in the
    // centre, which is where a backlog belongs anyway.
    readonly property int maxInToast: 5

    // Only the top of an open pack folds it back, exactly as the centre does
    // it (NotificationPane's bottomMargin trick) - the entries underneath are
    // their own targets.
    readonly property real headBand: 28 * uiScale
    // Past this much of the plate.s width, letting go throws it away. A third
    // was a long way to push something you have already decided about; this is
    // about 55px, and the flick below means you usually travel less than that.
    readonly property real throwFraction: 0.16
    // …or let go while still moving right at this speed (px/ms) and it goes
    // whatever the distance. Distance OR velocity, because a decisive flick
    // and a careful push are both "yes" and only one of them is far.
    readonly property real flickSpeed: 0.55
    // A press that travelled less than this was a click, not an abandoned
    // throw. Without it every dismissal would also fire the app's action on
    // the way out.
    readonly property real tapSlop: 5

    // Fired when a click lands on a notification that is not a collapsed
    // pack. ControlPanel decides what that means; this only knows that you
    // asked for it.
    signal activated(var record)

    // [{ items, born, leaving, app, open, urgency }] - newest item first
    property var live: []

    function lifeFor(urgency) {
        return urgency === NotificationUrgency.Low ? lifeLowMs : lifeMs;
    }

    // Critical does not expire. A battery at 3% that cleared itself after six
    // seconds because you happened to be looking elsewhere is the one failure
    // this whole surface exists to prevent.
    function expires(urgency) {
        return urgency !== NotificationUrgency.Critical;
    }

    // @accentLineColor@ and NOT @greenColor@.
    //
    // The two are the same colour in dark and deliberately are not in light.
    // @greenColor@ is base0B, which light puts at #94E1B0 - a pale mint that
    // is fine as a filled count badge with dark ink on it and measures
    // 1.24:1 as a stroke on this plate. The wire and the life bar were being
    // drawn correctly and could not be seen. @downColor@ and @mutedColor@
    // were already polarity-correct; this was the one that was not.
    function wireColorFor(urgency) {
        if (urgency === NotificationUrgency.Critical) return "@downColor@";
        if (urgency === NotificationUrgency.Low) return "@mutedColor@";
        return "@accentLineColor@";
    }

    // ---- EVERY per-toast fact lives in `live`, never in the delegate ----
    //
    // This is the single most important rule in this file, and it is not
    // obvious. `live` is a plain JS array, and reassigning a JS array as a
    // Repeater's model DESTROYS AND RECREATES EVERY DELEGATE - not just the
    // one that changed. So any state a delegate declares for itself is reset
    // whenever *any other* toast arrives, is dismissed, or is expanded.
    //
    // A life clock kept in the delegate therefore never fires: a Signal toast
    // four seconds into its six would be handed a fresh six the moment a
    // Syncthing notification showed up next to it, and on a busy desktop
    // nothing would ever expire. (It is the same trap whether the clock is an
    // accumulator or an animation - both are delegate-local.) `expiresAt` is
    // an absolute timestamp in the model, so a rebuilt delegate picks the
    // clock back up exactly where it was.
    //
    // Identity is `id`, a counter, and not `born`. Two notifications from
    // different apps in the same millisecond share a `born`, and dismissing
    // one would dismiss both.
    property int nextId: 1

    // `arrive` is "this entry has never been on screen". It is what drives
    // the fly-in, and it is a flag in the model rather than a timestamp
    // comparison in the delegate for the reason everything else here is:
    // the delegate is not a reliable place to measure anything.
    //
    // It replaced `Date.now() - born < 150`, which was a wall-clock race in
    // a render path - the window is open for 150ms and closes whether or
    // not a delegate was built inside it, so one GC pause between `show()`
    // and the Repeater meant the entrance silently never played and the
    // toast popped in. The flag has no window: it is cleared by the first
    // delegate built from the entry, in place, so a REBUILT delegate (which
    // is already on screen and must not re-fly) sees it false.
    function entry(id, items, app, urgency, born, open, expiresAt, arrive) {
        return {
            id: id, items: items, app: app, urgency: urgency,
            born: born, open: open, leaving: false,
            arrive: arrive === true,
            // 0 means "never expires" - that is Critical.
            expiresAt: expiresAt,
            // True while you are holding or hovering it; see setHeld.
            held: false,
            // Where a thrown plate was let go, so the rebuilt delegate can
            // carry on from there instead of snapping back to rest.
            thrownFrom: 0
        };
    }

    function deadlineFor(urgency) {
        return expires(urgency) ? Date.now() + lifeFor(urgency) : 0;
    }

    // A pack keeps the STRONGEST urgency it holds. Taking the newest one's
    // would let a routine notification packing into a critical battery
    // warning hand it an expiry, and quietly clear the one thing on this
    // surface that is not allowed to clear itself.
    // Only two Lows make a Low. Written the other way round - "neither is
    // Normal, so it is Low" - anything with no urgency at all fell through
    // to Low and a packed toast came out grey and short-lived, which is the
    // wrong default for something you could not classify.
    function strongest(a, b) {
        if (a === NotificationUrgency.Critical
            || b === NotificationUrgency.Critical) return NotificationUrgency.Critical;
        if (a === NotificationUrgency.Low
            && b === NotificationUrgency.Low) return NotificationUrgency.Low;
        return NotificationUrgency.Normal;
    }

    // A second notification from an app that already has a toast up packs
    // into it rather than opening another. Two toasts side by side saying
    // "system" is the stack telling you about itself; one saying "system
    // x2" is the stack telling you about the world. The clock restarts, so
    // a conversation keeps one toast alive instead of marching a column
    // down your screen.
    function show(record) {
        const app = record.appName || "Unknown app";
        const now = Date.now();

        for (let i = 0; i < live.length; i++) {
            if (live[i].leaving || live[i].app !== app) continue;
            const prev = live[i];
            const next = live.slice();
            // An OSD REPLACES its predecessor instead of packing into it.
            // Five volume presses are one reading that changed, not five
            // things that happened: a count badge and a backlog to open
            // would both be lying about what you did.
            const merged = record.transient
                ? [record]
                : [record].concat(prev.items).slice(0, maxInToast);
            const urgency = record.transient
                ? record.urgency
                : strongest(prev.urgency, record.urgency);
            next[i] = entry(prev.id, merged, app, urgency, now,
                            record.transient ? false : prev.open,
                            deadlineFor(urgency), true);
            live = next;
            return;
        }

        // Over the ceiling, the oldest goes out through retire() so it
        // slides and fades like every other dismissal. Slicing it out of
        // the array instead made it disappear between two frames - and
        // took any toast that happened to be mid-exit with it, cutting
        // that animation off at whatever frame it had reached.
        //
        // Leaving toasts stay in the array until the reaper has them, and
        // do not count against the ceiling: they are already on their way
        // out, and holding a slot for them would mean a burst of three
        // arrivals showed one toast.
        const alive = live.filter(t => !t.leaving);
        for (let i = maxShown - 1; i < alive.length; i++) retire(alive[i].id);

        // Read back AFTER the loop: retire() reassigns `live`.
        const next = live.slice();
        next.unshift(entry(nextId++, [record], app, record.urgency, now,
                           false, deadlineFor(record.urgency), true));
        live = next;
    }

    // `fromX` is where a thrown plate was released. Carried into the model so
    // the rebuilt delegate starts there and keeps flying, instead of jumping
    // back to its resting place for a frame first.
    function retire(id, fromX) {
        const next = live.map(t => {
            if (t.id !== id) return t;
            const e = entry(t.id, t.items, t.app, t.urgency, t.born,
                            t.open, t.expiresAt);
            e.leaving = true;
            e.thrownFrom = fromX || 0;
            return e;
        });
        live = next;
        reaper.restart();
    }

    // Clicking a packed toast opens it where it stands, rather than making
    // you go to the centre to find out what the count was hiding. Opening
    // also stops the clock: you are reading it.
    //
    // Not an arrival: `entry` is called without the last argument, so
    // `arrive` is false and the rebuilt delegate does not replay the fly-in
    // or redraw the wire from nothing while the plate is growing. (`born`
    // is carried over unchanged for the same reason, from back when
    // freshness was measured off it.)
    function toggle(id) {
        live = live.map(t =>
            t.id !== id ? t
                        : entry(t.id, t.items, t.app, t.urgency, t.born,
                                !t.open, t.expiresAt));
    }

    // Hovering or holding stops the clock - the sweep does the actual
    // stopping, this only records that you have hold of it.
    //
    // Mutated IN PLACE on purpose: reassigning `live` here would rebuild
    // every delegate on the desktop every time the pointer crossed a toast.
    function setHeld(id, held) {
        for (const t of live) if (t.id === id) { t.held = held; return; }
    }

    // Handling a toast and putting it back gives it its life over.
    function renew(id) {
        for (const t of live)
            if (t.id === id) { t.expiresAt = deadlineFor(t.urgency); return; }
    }

    visible: live.length > 0

    anchors { top: true; right: true }
    margins { top: 14 * uiScale; right: 14 * uiScale }

    // TWICE the plate's width.
    //
    // A toast thrown to the right travels its own width and then some, and
    // a child leaving the layer surface is CLIPPED by it - at the old
    // `implicitWidth: toastWidth` the dismissal looked like the plate
    // dissolving into an invisible wall a few pixels from where it started.
    // The extra width is empty and stays click-through because the mask
    // below covers the plates and not the window.
    implicitWidth: toastWidth * 2 * uiScale

    // Quantised, for the same kind of reason the width is doubled: a layer
    // surface is not free to resize.
    //
    // The plate animates its height over `expandMs` when a pack opens, the
    // column's implicitHeight follows it, and this followed that - so
    // opening a pack asked the compositor to resize and reconfigure the
    // surface on every frame of the animation. Rounding up to a step makes
    // that a handful of resizes instead of one per frame, and costs
    // nothing: the slack is transparent and sits outside `mask`, exactly
    // like the empty half of the width.
    readonly property real heightStep: 48 * uiScale
    implicitHeight: Math.max(
        1, Math.ceil(column.implicitHeight / heightStep) * heightStep)

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "laser-bar-toasts"
    WlrLayershell.layer: WlrLayer.Overlay
    // Never takes the keyboard. A notification arriving must not steal a
    // keystroke from whatever you are in the middle of typing.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // The plates only, never the whole window. Half of this surface is the
    // headroom a throw needs and the desktop underneath has to stay usable.
    mask: Region { item: column }

    Column {
        id: column
        // Right-aligned inside the oversized window, so the plates sit where
        // they always did and the headroom is all on the left.
        x: parent.width - width
        width: root.toastWidth * root.uiScale
        spacing: 8 * root.uiScale

        // When one toast goes, the ones below slide up into the gap rather
        // than jumping - and when one arrives, the rest slide down.
        move: Transition {
            NumberAnimation { properties: "y"; duration: root.moveMs
                              easing.type: Easing.OutCubic }
        }
        add: Transition {
            NumberAnimation { properties: "y"; duration: root.moveMs
                              easing.type: Easing.OutCubic }
        }

        Repeater {
            model: root.live

            Item {
                id: toast
                required property var modelData
                required property int index

                width: column.width
                height: plate.height

                // A delegate can be rebuilt when the list changes, and
                // replaying the arrival for every toast every time anything
                // arrives would be a mess. Only something genuinely new
                // flies in; a rebuilt one is simply already there.
                //
                // Read off the model (see `entry`), and cleared on the
                // model below. The binding has no change notification
                // behind it, so it stays true for THIS delegate's whole
                // life - which is what the arrival animations want - while
                // the next delegate built from the same entry reads false.
                readonly property bool fresh: modelData.arrive === true

                // Children's Component.onCompleted run before this one, so
                // the wire's own `if (!toast.fresh)` below still sees the
                // flag set.
                Component.onCompleted: {
                    const e = root.live[index];
                    if (e) e.arrive = false;
                }

                readonly property var head: modelData.items[0]
                readonly property bool packed: modelData.items.length > 1

                // How far the plate has been dragged, and whether letting go
                // would throw it away.
                property real dragX: 0
                readonly property bool willThrow:
                    dragX > width * root.throwFraction
                    || (dragVel > root.flickSpeed && dragX > 8)

                // Rightward pointer speed at the last sample, px/ms.
                property real dragVel: 0

                // Arrival and departure drive THIS, never plate.x directly.
                // A NumberAnimation writing a property that already has a
                // binding destroys the binding - animating plate.x would
                // have killed the drag on the first toast that flew in.
                property real offsetX: 0
                property real fadeIn: 1

                // True for the whole gesture, flipped by hand rather than read
                // off MouseArea.pressed: whether `pressed` is already false
                // when `onReleased` runs is Qt signal-ordering trivia, and if
                // it is still true the Behavior below is disabled and the
                // spring back is a jump instead of a movement.
                property bool dragging: false

                // The spring back when a throw is abandoned.
                Behavior on dragX {
                    enabled: !toast.dragging
                    NumberAnimation { duration: root.exitMs
                                      easing.type: Easing.OutCubic }
                }

                Rectangle {
                    id: plate
                    x: toast.dragX + toast.offsetX
                    width: parent.width
                    height: body.implicitHeight + 20 * root.uiScale
                    radius: 12 * root.uiScale
                    color: "@sheetBg@"
                    border.width: 1
                    border.color: "@glassBorder@"
                    clip: true

                    // NOT faded while dragging, deliberately.
                    //
                    // An Item with clip:true, several children and an opacity
                    // below 1 has to be rendered to an offscreen texture and
                    // composited - every single frame. Binding opacity to the
                    // drag meant the plate left 1.0 on the first pixel of
                    // movement and then paid for that composite on every
                    // frame of the gesture, which is what made dragging feel
                    // heavy. The throw is short and ends in an animation that
                    // fades it anyway; nothing is lost by staying opaque.
                    opacity: toast.fadeIn

                    // Opening a pack grows the plate rather than snapping it.
                    Behavior on height {
                        NumberAnimation { duration: root.expandMs
                                          easing.type: Easing.OutCubic }
                    }

                    BeamWire {
                        id: wire
                        // Wide enough for the bar's amplitude at `scale`:
                        // the tallest strand reaches 8 * scale either side of
                        // the centreline, plus half a 9 * scale stroke.
                        width: 24 * root.uiScale

                        // The PLATE'S FULL HEIGHT.
                        //
                        // `clip: true` clips to a bounding RECTANGLE and not
                        // to the rounded corners, so a wave at full amplitude
                        // up there paints outside the pill. Insetting by the
                        // radius fixed that and cost two dozen pixels of
                        // length, which was the wrong trade: the wire is the
                        // edge of the plate, and an edge that stops short of
                        // both corners reads as a stub.
                        //
                        // So it runs the whole way and BeamWire tapers the
                        // wave onto its centreline over `endRamp` at each
                        // end instead - narrow enough by the corners to stay
                        // inside the arc, full length everywhere else.
                        height: parent.height
                        endRamp: plate.radius

                        uiScale: root.uiScale
                        wireColor: root.wireColorFor(toast.modelData.urgency)
                        active: root.visible
                        reveal: 0

                        // Drawn down the edge as the toast lands, 40ms behind
                        // the plate so the plate arrives first.
                        SequentialAnimation {
                            running: toast.fresh && !toast.modelData.leaving
                            PauseAnimation { duration: root.wireDelayMs }
                            NumberAnimation {
                                target: wire; property: "reveal"
                                from: 0; to: 1
                                duration: root.wireDrawMs
                                easing.type: Easing.OutCubic
                            }
                        }
                        // A rebuilt delegate is already there; it must not sit
                        // at reveal 0 waiting for an arrival that will not run.
                        Component.onCompleted:
                            if (!toast.fresh) wire.reveal = 1
                    }

                    Column {
                        id: body
                        // Clear of the wire, which is wider than the rule it
                        // replaced and whose strands swing either side of
                        // their own centreline.
                        x: 30 * root.uiScale
                        y: 10 * root.uiScale
                        width: parent.width - 43 * root.uiScale
                        spacing: 6 * root.uiScale

                        NotificationHead {
                            width: parent.width
                            uiScale: root.uiScale
                            appName: toast.modelData.app
                            appIcon: toast.head ? toast.head.appIcon : ""
                            image: toast.head ? toast.head.image : ""
                            count: toast.modelData.items.length
                            hintText: toast.packed
                                ? (toast.modelData.open ? "collapse" : "expand") : ""
                            timeText: root.clock && toast.head
                                ? root.clock.relative(toast.head.ts) : ""
                        }

                        Repeater {
                            model: toast.modelData.open
                                ? toast.modelData.items
                                : toast.modelData.items.slice(0, 1)

                            NotificationRow {
                                id: entryRow
                                required property var modelData
                                required property int index
                                width: body.width
                                uiScale: root.uiScale
                                item: modelData
                                // The head names the app and draws the icon
                                // once, above the whole pack. They are all
                                // from the same app - that is what packing is.
                                showApp: false
                                showIcon: false

                                // Each one a beat behind the last, so an
                                // opening pack reads as unfolding rather than
                                // as a block arriving.
                                opacity: index === 0 ? 1 : 0
                                Component.onCompleted: if (index > 0) reveal.start()
                                SequentialAnimation {
                                    id: reveal
                                    PauseAnimation { duration: 30 + entryRow.index * 40 }
                                    NumberAnimation {
                                        // entryRow, not `parent`: inside an
                                        // animation `parent` is the
                                        // SequentialAnimation, so this
                                        // silently animated nothing and the
                                        // rows past the first stayed at
                                        // opacity 0 - holding their height
                                        // and leaving the pack looking empty.
                                        target: entryRow; property: "opacity"
                                        to: 1; duration: 110
                                    }
                                }
                            }
                        }
                    }

                    // How long it has left, lying along the bottom edge in
                    // the same green - the wire laid down. It is the only
                    // answer to "is this about to vanish?" that does not
                    // require guessing.
                    Rectangle {
                        id: lifeBar
                        visible: root.expires(toast.modelData.urgency)
                                 && !toast.modelData.leaving

                        // A SHRINKING WINDOW onto a rectangle that never moves.
                        //
                        // The bar has to reach the very left of the pill, and
                        // at the bottom-most row the pill is not there yet -
                        // its corner has curved away. So the thing being drawn
                        // is a rectangle carrying the PLATE'S OWN radius, tall
                        // enough for that curve to develop, and this item is a
                        // 3px-tall clip across it. `clip` is rectangular,
                        // which is exactly right for cutting a strip, and the
                        // strip it leaves has the plate's corner built into
                        // its left end.
                        //
                        // The level is this window's WIDTH, and the rectangle
                        // underneath keeps its full size always. Shrinking the
                        // rectangle instead was wrong in a way that only
                        // showed in the last moment of the drain: Qt clamps
                        // `radius` to half the shorter side, so once the bar
                        // narrowed past twice the radius its left corner
                        // straightened out, stopped matching the plate's
                        // curve, and poked outside the pill.
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        height: 3 * root.uiScale
                        clip: true
                        color: "transparent"

                        // Read through `root.live`, NOT through `modelData`.
                        //
                        // With a JS array as the model, `modelData` is a
                        // SNAPSHOT taken when the delegate was built - not a
                        // live handle on the array element. The sweep pushes
                        // `expiresAt` forward in place while a toast is held,
                        // and a binding on `modelData.expiresAt` never sees
                        // any of it: the bar carried on draining under the
                        // pointer and emptied while the toast itself was not
                        // going anywhere. (Measured, not guessed - a toast
                        // pinned at 4% remaining rendered a 60% bar, which is
                        // exactly the un-held drain from its original
                        // deadline.)
                        //
                        // Indexing the array re-reads the real object. This
                        // binding already re-evaluates on every `tickNow`, so
                        // it picks up in-place changes on the next tick
                        // without anything having to notify.
                        //
                        // NOT named `left`: that is Item.left, an anchor
                        // line, and QML refuses to let a property shadow it -
                        // "Cannot override FINAL property", at load time.
                        readonly property real remaining: {
                            root.tickNow;              // the heartbeat
                            const e = root.live[toast.index];
                            if (!e || !e.expiresAt) return 1;
                            return Math.max(0, Math.min(1,
                                (e.expiresAt - root.tickNow) / toast.span));
                        }

                        // Derived from `tickNow` rather than animated, which
                        // is what keeps it cheap - see the sweep. The Behavior
                        // only smooths BETWEEN those ten steps a second, which
                        // on a bar this thick is the difference between a
                        // drain and a ratchet.
                        width: plate.width * remaining
                        Behavior on width {
                            NumberAnimation { duration: 100
                                              easing.type: Easing.Linear }
                        }

                        Rectangle {
                            // Pinned to the PLATE's bottom-left and always its
                            // full width, so its corner is the plate's corner
                            // whatever the level above has done.
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            width: plate.width
                            height: plate.radius * 2
                            radius: plate.radius
                            // Full alpha, which is also what the comment
                            // above always claimed: "the wire laid down".
                            // It was 0.55, to sit under the wire rather
                            // than beside it - but a 3px strip does not
                            // compete with a full-height wave, and the
                            // discount cost the light variant the floor the
                            // colour had just been picked to clear (3.2:1
                            // at full, 1.87:1 at 0.55).
                            color: root.wireColorFor(toast.modelData.urgency)
                        }
                    }

                    MouseArea {
                        id: drag
                        anchors.fill: parent
                        hoverEnabled: true

                        property real pressX: 0
                        property real pressY: 0
                        property bool moved: false
                        property real lastX: 0
                        property real lastT: 0

                        onPressed: mouse => {
                            toast.dragging = true;
                            pressX = mouse.x; pressY = mouse.y; moved = false;
                            lastX = mouse.x; lastT = Date.now();
                            toast.dragVel = 0;
                        }
                        onPositionChanged: mouse => {
                            if (!pressed) return;
                            const dx = mouse.x - pressX;
                            if (Math.abs(dx) > root.tapSlop) moved = true;

                            // Speed at the last sample, not averaged over
                            // the whole gesture: a slow drag that ends in a
                            // flick should count as a flick.
                            const now = Date.now();
                            const dt = now - lastT;
                            if (dt > 0) {
                                toast.dragVel = (mouse.x - lastX) / dt;
                                lastX = mouse.x; lastT = now;
                            }

                            // Rightward throws freely; leftward resists, so
                            // the two directions do not feel like one axis.
                            toast.dragX = dx >= 0 ? dx : dx * 0.32;
                        }
                        onReleased: {
                            toast.dragging = false;
                            if (toast.willThrow) {
                                // The delegate is about to be destroyed and
                                // rebuilt by retire(), so setting dragX here
                                // would be thrown away before a single frame
                                // drew. Hand the release position to the
                                // model and let the rebuilt plate carry on
                                // from there.
                                root.retire(toast.modelData.id, toast.dragX);
                                return;
                            }
                            toast.dragX = 0;

                            // Handling a toast and putting it back gives it
                            // its life over. You just had hold of it; having
                            // it expire out from under your finger because
                            // the clock happened to run out mid-gesture is
                            // the shell being pedantic at you.
                            root.renew(toast.modelData.id);

                            if (moved) return;

                            // ---- what a click means, in order ----
                            //
                            // A collapsed pack EXPANDS, and that beats the
                            // app action outright: the action belongs to one
                            // notification and a pack is several, so firing
                            // it would mean picking one of them for you.
                            if (toast.packed && !toast.modelData.open) {
                                root.toggle(toast.modelData.id);
                                return;
                            }
                            // Open pack, pressed on its header: fold it back.
                            if (toast.packed && toast.modelData.open
                                && pressY <= root.headBand) {
                                root.toggle(toast.modelData.id);
                                return;
                            }
                            // Otherwise it is the action for this one - and
                            // the toast goes with it. Acting on a
                            // notification is done with it, and a Critical
                            // one never expires, so without this a click
                            // left it on screen on top of whatever the
                            // action just opened.
                            root.activated(toast.head);
                            root.retire(toast.modelData.id);
                        }
                    }
                }

                // ---- arrival ----
                ParallelAnimation {
                    running: toast.fresh && !toast.modelData.leaving
                    NumberAnimation {
                        target: toast; property: "offsetX"
                        from: root.flyTravel; to: 0
                        duration: root.flyMs; easing.type: Easing.OutBack
                        easing.overshoot: root.flyOvershoot
                    }
                    NumberAnimation {
                        target: toast; property: "fadeIn"
                        from: 0; to: 1; duration: root.fadeMs
                    }
                }

                // ---- departure ----
                NumberAnimation {
                    running: toast.modelData.leaving
                    target: toast; property: "offsetX"
                    // A thrown plate resumes from where your hand left it
                    // and carries off the edge; anything else - expired,
                    // clicked - takes the short slide.
                    from: toast.modelData.thrownFrom
                    to: toast.modelData.thrownFrom > 0
                        ? toast.width + 80 * root.uiScale
                        : toast.width * 0.4
                    duration: root.exitMs; easing.type: Easing.InCubic
                }

                // The fade belongs HERE and not on the drag: one offscreen
                // composite for the length of the exit is nothing, one per
                // frame of every gesture is what you feel.
                NumberAnimation {
                    running: toast.modelData.leaving
                    target: toast; property: "fadeIn"
                    to: 0; duration: root.exitMs
                }

                // ---- the life clock, as the delegate sees it ----
                //
                // Both derived from the model, so a rebuilt delegate shows
                // the right thing. `remaining` is captured once at creation
                // on purpose: it seeds the drain animation, and rebinding it
                // every sweep would restart that animation four times a
                // second.
                readonly property real span: root.lifeFor(modelData.urgency)

                // Hovering holds the clock - you are reading it - and so does
                // holding the button down, which is NOT the same thing.
                //
                // A leftward drag only moves the plate 32% of the pointer.s
                // travel, so the pointer outruns it and leaves the plate.
                // With this bound to hover alone, `containsMouse` went false
                // mid-gesture, the life clock restarted under the drag, and a
                // toast near the end of its life expired the moment you let
                // go: it snapped back to its resting place for one frame and
                // then vanished. Pressed counts as held.
                readonly property bool held: drag.containsMouse || drag.pressed
                // Pushed into the model, which is where the clock lives.
                onHeldChanged: root.setHeld(modelData.id, held)
            }
        }
    }

    // One sweep for every toast, reading the deadline out of the MODEL.
    //
    // It compares numbers and touches no layout, so it is nothing like the
    // cost of the per-frame width animation it replaced - but it has to
    // exist, and it has to read `live` rather than the delegates, because a
    // delegate is rebuilt whenever any other toast changes and anything it
    // was counting goes back to zero with it.
    // Also the heartbeat the life bars are drawn from, hence 100ms rather
    // than something lazier - see lifeBar.
    property real tickNow: Date.now()

    property real lastTick: Date.now()

    Timer {
        interval: 100
        running: root.visible
        repeat: true

        // `lastTick` only advances inside onTriggered, and this timer stops
        // whenever no toast is up. Without re-stamping it here, the first
        // tick after a toast appears measures `elapsed` across the entire
        // quiet stretch since the last one - minutes, possibly - and hands
        // all of it to any HELD toast as extra life. A notification you
        // happened to be hovering as it arrived would sit there for the rest
        // of the afternoon.
        onRunningChanged: if (running) root.lastTick = Date.now()

        onTriggered: {
            const now = Date.now();
            const elapsed = now - root.lastTick;
            root.lastTick = now;
            root.tickNow = now;

            // Collected first, retired after the walk. retire() reassigns
            // `live`, so it cannot be called from inside the loop - which
            // used to be handled with a `return`, and that quietly cost
            // every entry AFTER the expired one its share of this tick: a
            // held toast sitting below one that timed out stopped being
            // held for 100ms, and only one toast could ever retire per
            // tick however many had run out.
            const done = [];
            for (const t of root.live) {
                if (t.leaving || !t.expiresAt) continue;
                // Hovering it or having it open means you are reading it, so
                // the deadline is pushed along with real time and never gets
                // any closer. That freezes the bar too, for free - it is
                // drawn from the same number.
                if (t.held || t.open) { t.expiresAt += elapsed; continue; }
                if (now >= t.expiresAt) done.push(t.id);
            }
            for (const id of done) root.retire(id);
        }
    }

    // Clears out whatever has finished its exit animation.
    Timer {
        id: reaper
        interval: root.exitMs + 20
        repeat: false
        onTriggered: root.live = root.live.filter(t => !t.leaving)
    }
}
