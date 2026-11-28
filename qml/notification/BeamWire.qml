import QtQuick
import QtQuick.Shapes

// The laser bar's wire, running down the edge of a notification.
//
// This is BeamSide.qml's strand maths unchanged in shape - sine strands,
// each with its own phase offset, speed and amplitude, a soft wide pass under
// a crisp thin one, over a near-straight bright core - turned on its side and
// scaled to a plate instead of a screen. The flat 2px rule it replaces said
// "accent colour"; this says "the bar did that".
//
// `reveal` is the travelling tip. Amplitude ramps to zero at the leading end
// exactly as the bar's does, which is the detail that stops the wire arriving
// as a straight line that only becomes a wave once it is fully out. Animate
// it 0 -> 1 and the wire is DRAWN down the edge as the toast lands.
Item {
    id: root

    property real uiScale: 1
    property color wireColor: "@greenColor@"
    // 0..1 of the height. See above - this is the arrival, not a clip.
    property real reveal: 1
    // Gated: this drives a repeating timer. Bound to the toast's own
    // visibility by its caller, so a wire never animates off screen.
    property bool active: false

    // Eight, where the bar runs five. The bar.s strands are spread over a
    // whole screen edge; these are packed into a band a couple of dozen
    // pixels wide, so it takes more of them to read as a braid rather than
    // as a few separate lines. The maths below cycles amplitude on s % 3 and
    // offsets phase by s, so any count works without further tuning.
    readonly property int strandCount: 8

    // Every number below is BeamSide's, multiplied by one factor.
    //
    // `scale` is the CROSS-SECTION - amplitude and stroke width together,
    // which is the whole of what "thicker" means. The bar's own values are
    // written out literally so the two can be compared at a glance:
    // amplitude (8 + (s%3)*4), strokes 9 under 4, core 8 under 3.
    property real scale: 0.5

    // Wavelength deliberately does NOT take `scale` - thickness and period
    // are separate dials, and this one is tighter than the bar's.
    readonly property real wavelengthScale: 0.75

    // How far the wave travels per tick. Tighter coils pass a given point
    // more often at the same phase rate, so a shorter wavelength reads as
    // FASTER unless this comes down with it - these two are tuned together
    // or not at all. BeamSide advances 0.1 per 33ms; this is well under half
    // that, which at this period gives a slow drift rather than a scroll.
    readonly property real phaseStep: 0.035

    // How far from each end the wave flattens onto its own centreline.
    //
    // BeamSide deliberately does NOT do this - its comment says an edge ramp
    // "squashed every strand onto the centreline over the first 20px, so the
    // bar started as a single line and only became a wave once clear of the
    // border". That is right for the bar, which begins at a screen edge and
    // has nothing to avoid.
    //
    // Here it is load-bearing for the opposite reason. The plate's corners
    // are rounded and `clip: true` only clips to a bounding RECTANGLE, so a
    // wave at full amplitude in the corner paints outside the pill. Tapering
    // into the corners lets the wire run the plate's whole height instead of
    // being cut short of it - length that an inset would have cost.
    //
    // In FINAL PIXELS, the same space as `width` and `height` - not in
    // design units like `scale` and the amplitudes below. The maths used to
    // multiply this by uiScale as well, while its only caller passes
    // `plate.radius`, which is already `12 * uiScale`: the taper was
    // uiScale LONG at any scale but 1, which is the one the toasts happen
    // to use. One unit, stated here, and the default scales itself.
    property real endRamp: 14 * uiScale
    // Never zero: `t / 0` at t = 0 is NaN, Math.min propagates it, and a
    // single Qt.point(NaN, 0) takes the whole polyline with it.
    readonly property real rampLen: Math.max(1, endRamp)

    // Advancing a phase and letting PathPolyline.path rebind is what
    // BeamSide does, and for the reason documented there: it keeps the
    // geometry on the GPU instead of repainting a Canvas by hand.
    // 20Hz, not the bar's 30. The bar's wave is a full-screen hero you look
    // straight at while you hold the key; this is a narrow band of trim on
    // something you read. The phase step is scaled to match so the wire
    // travels at the same speed it always did.
    readonly property int tickMs: 50
    property real wavePhase: 0
    Timer {
        interval: root.tickMs
        running: root.active
        repeat: true
        onTriggered: root.wavePhase += root.phaseStep * (root.tickMs / 33)
    }

    // ShapePath.strokeColor bakes its own alpha in, so the layered passes
    // need the colour rebuilt per alpha. Same helper as BeamSide.
    function alphaColor(c, a) {
        const k = Qt.color(c);
        return Qt.rgba(k.r, k.g, k.b, a);
    }

    // Both passes below need the same points. Computed once per phase tick
    // and read twice, rather than each Repeater running the maths itself -
    // the same cache BeamSide keeps, for the same reason.
    property var strandCache: []

    // ---- the sample grid, which the phase does NOT move ----
    //
    // `t` and the end taper depend only on the height, the reveal and
    // endRamp. The phase moves `x` and nothing else. Recomputing the ramp
    // nine times per tick (eight strands and the core) was most of the
    // arithmetic in the only thing on a toast that runs continuously, so it
    // is hoisted into a grid rebuilt when the geometry changes - which,
    // once a toast has landed, is never.
    //
    // 3.5px steps, not 2. Every point is still a Qt.point allocation per
    // strand per tick, and nobody can see 2px sampling on a wave that is
    // four pixels tall.
    property var gridT: []
    property var gridRamp: []

    function rebuildGrid() {
        const grown = root.height * root.reveal;
        const ts = [];
        const ramps = [];
        if (grown > 0) {
            const step = 3.5 * root.uiScale;
            const len = root.rampLen;
            for (let t = 0; t <= grown; t += step) {
                ts.push(t);
                // Both ends: the tip because it is still arriving, the root
                // because that end sits in the plate's rounded corner. See
                // `endRamp` for why this is the opposite of what BeamSide
                // does.
                ramps.push(Math.min(1, t / len, (grown - t) / len));
            }
        }
        gridT = ts;
        gridRamp = ramps;
    }

    function strandPoints(s) {
        const ts = root.gridT;
        if (ts.length === 0) return [];
        const ramps = root.gridRamp;
        const mid = root.width / 2;
        const phaseOffset = s * 1.05;
        const speedFactor = 1 + s * 0.08;
        const amplitude = (8 + (s % 3) * 4) * root.scale * root.uiScale;
        const wavelength = (11 + s) * root.wavelengthScale * root.uiScale;
        const phase = root.wavePhase * speedFactor + phaseOffset;
        const pts = [];
        for (let i = 0; i < ts.length; i++) {
            const t = ts[i];
            const x = mid + amplitude * ramps[i] * Math.sin(t / wavelength + phase);
            pts.push(Qt.point(x, t));
        }
        return pts;
    }

    function corePoints() {
        const ts = root.gridT;
        if (ts.length === 0) return [];
        const ramps = root.gridRamp;
        const mid = root.width / 2;
        const amplitude = 1.5 * root.scale * root.uiScale;
        const wavelength = 12 * root.wavelengthScale * root.uiScale;
        const phase = root.wavePhase * 1.2;
        const pts = [];
        for (let i = 0; i < ts.length; i++) {
            const t = ts[i];
            const x = mid + amplitude * ramps[i] * Math.sin(t / wavelength + phase);
            pts.push(Qt.point(x, t));
        }
        return pts;
    }

    function rebuild() {
        const next = [];
        for (let s = 0; s < strandCount; s++) next.push(strandPoints(s));
        strandCache = next;
        coreCache = corePoints();
    }
    property var coreCache: []

    // The phase only moves x, so it rebuilds the points and not the grid.
    // Anything that changes the geometry has to do both, in that order.
    onWavePhaseChanged: rebuild()
    onHeightChanged: { rebuildGrid(); rebuild() }
    onRevealChanged: { rebuildGrid(); rebuild() }
    onRampLenChanged: { rebuildGrid(); rebuild() }
    onUiScaleChanged: { rebuildGrid(); rebuild() }
    Component.onCompleted: { rebuildGrid(); rebuild() }

    Shape {
        id: wireShape
        anchors.fill: parent
        // CurveRenderer, for ANTIALIASING.
        //
        // This was switched to the default geometry renderer while hunting a
        // drag stutter, on the theory that the curve path was expensive. It
        // was not: of the 12.8% a toast cost, dropping this and halving the
        // sample rate together recovered 1.6 points, while the real culprit
        // - a continuously animating life bar forcing a 60Hz repaint - was
        // worth about seven on its own.
        //
        // What it did cost was smoothness. The geometry renderer tessellates
        // to triangles with hard edges and has no antialiasing of its own, so
        // five thin diagonal strokes came out visibly stepped. CurveRenderer
        // resolves the curve analytically on the GPU and antialiases as it
        // goes, which is the whole reason it exists.
        preferredRendererType: Shape.CurveRenderer
        asynchronous: false

        // Soft pass, the bar's 9px glow under its 4px line, both at `scale`.
        //
        // Repeater can only instantiate Item-typed delegates, and ShapePath
        // is not an Item - a ShapePath used directly as a delegate fails
        // SILENTLY, drawing nothing at all. (That is not a guess: the first
        // version of this file did exactly that and rendered only the core,
        // which is near-straight by design, so the wire looked like the flat
        // rule it was meant to replace.) BeamSide hit it first and documents
        // the same workaround - wrap each one in an Item and push it into
        // the Shape's `data` by hand.
        Repeater {
            model: root.strandCount
            Item {
                property ShapePath shapePath: ShapePath {
                    strokeColor: root.alphaColor(root.wireColor, 0.10)
                    strokeWidth: 9 * root.scale * root.uiScale
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: root.strandCache[index] || [] }
                }
                Component.onCompleted: wireShape.data.push(shapePath)
            }
        }
        Repeater {
            model: root.strandCount
            Item {
                property ShapePath shapePath: ShapePath {
                    strokeColor: root.alphaColor(root.wireColor, 0.5)
                    strokeWidth: 4 * root.scale * root.uiScale
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: root.strandCache[index] || [] }
                }
                Component.onCompleted: wireShape.data.push(shapePath)
            }
        }

        // The bright core the strands weave around.
        ShapePath {
            strokeColor: root.alphaColor(root.wireColor, 0.22)
            strokeWidth: 8 * root.scale * root.uiScale
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathPolyline { path: root.coreCache }
        }
        ShapePath {
            strokeColor: root.wireColor
            strokeWidth: 3 * root.scale * root.uiScale
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathPolyline { path: root.coreCache }
        }
    }
}
