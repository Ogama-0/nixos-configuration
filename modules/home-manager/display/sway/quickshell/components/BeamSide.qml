import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// One side of the laser bar: three stacked glow layers (blurred, fading
// from the accent color at the screen edge to white at the meeting tip), a
// bundle of animated sine strands over a bright core line (same technique
// as Music.qml's progress-bar waveform), and a slow "neon hum" opacity
// drift while shown. LaserBar.qml instantiates this twice, once per side,
// with `side`/`accentColor` flipped.
Item {
    id: root

    required property string side // "left" or "right"
    required property string accentColor
    required property bool active
    required property real extent
    required property real panelWidth
    required property real beamY

    readonly property bool isLeft: side === "left"

    // Spans of panel x where a module clamps the wire. Amplitude ramps to zero
    // inside each, over `pinchPad` either side, so the strands flatten into a
    // capsule rather than crossing it. Same coordinate space as `extent`.
    property var pinchSpans: []
    readonly property real pinchPad: 20

    // The coloured band is not a rectangle. It runs at full height in the
    // open beam and eases down to the throat at a module's edge, so the beam
    // funnels into the capsule instead of being chopped off by it. Inside a
    // module's span the height collapses to zero - the capsule covers that
    // stretch anyway, and collapsing keeps the whole band one polygon rather
    // than one per gap.
    readonly property real bandHeight: 44
    property real throatHeight: 12
    property real funnelLead: 30

    function bandHalfAt(px) {
        let d = Infinity;
        for (let i = 0; i < pinchSpans.length; i++) {
            const a = pinchSpans[i][0];
            const b = pinchSpans[i][1];
            if (px >= a && px <= b) return 0;
            d = Math.min(d, px < a ? a - px : px - b);
        }
        if (!(d < funnelLead)) return bandHeight / 2;
        const t = d / funnelLead;
        // Smoothstep: flat in the open beam, steepest mid-funnel, flat again
        // into the throat. A straight taper reads as an angular wedge.
        const k = t * t * (3 - 2 * t);
        return (throatHeight + (bandHeight - throatHeight) * k) / 2;
    }

    property var bandPoints: []

    // Sampled where the silhouette actually curves, not uniformly. The open
    // beam is a straight line that needs two points; only the funnels either
    // side of a module need a fine step. Uniform sampling here produced a
    // ~900-point polygon and nearly doubled the bar's cost on its own.
    function bandBoundaries() {
        const xs = [0, extent];
        for (let i = 0; i < pinchSpans.length; i++) {
            const a = pinchSpans[i][0];
            const b = pinchSpans[i][1];
            const edges = isLeft
                ? [a - funnelLead, a, b, b + funnelLead]
                : [panelWidth - (b + funnelLead), panelWidth - b,
                   panelWidth - a, panelWidth - (a - funnelLead)];
            for (let j = 0; j < edges.length; j++) {
                const t = edges[j];
                if (t > 0 && t < extent) xs.push(t);
            }
        }
        xs.sort((p, q) => p - q);
        return xs;
    }

    function rebuildBand() {
        if (extent <= 0) { bandPoints = []; return; }
        const xs = bandBoundaries();
        const top = [];
        const bottom = [];
        const push = t => {
            const px = isLeft ? t : panelWidth - t;
            const half = bandHalfAt(px);
            top.push(Qt.point(px, beamY - half));
            bottom.unshift(Qt.point(px, beamY + half));
        };
        for (let i = 0; i < xs.length - 1; i++) {
            const from = xs[i];
            const to = xs[i + 1];
            const midPx = isLeft ? (from + to) / 2 : panelWidth - (from + to) / 2;
            const flat = Math.abs(bandHalfAt(midPx) - bandHalfAt(isLeft ? from : panelWidth - from)) < 0.01;
            if (flat) {
                push(from);
            } else {
                for (let t = from; t < to; t += 2) push(t);
            }
        }
        push(xs[xs.length - 1]);
        bandPoints = top.concat(bottom);
    }

    // Optional amplitude as a function of x, so one rail can carry a varying
    // signal (Wi-Fi strength) along its length. Deliberately not a second
    // BeamSide for the varying stretch: that would duplicate the blurred glow
    // layer and leave a visible seam where the two met.
    property var amplitudeAt: null

    function pinchScale(px) {
        if (!pinchSpans || pinchSpans.length === 0) return 1
        let scale = 1
        for (let i = 0; i < pinchSpans.length; i++) {
            const a = pinchSpans[i][0]
            const b = pinchSpans[i][1]
            if (px >= a && px <= b) return 0
            const d = px < a ? a - px : px - b
            if (d < pinchPad) scale = Math.min(scale, d / pinchPad)
        }
        return scale
    }

    // Right-anchored children (the glow layers below) resolve
    // `anchors.right: parent.right` against this width. Without it, root
    // defaults to width 0 and those anchors collapse to x: 0 instead of the
    // panel's actual right edge, rendering them off-screen.
    width: panelWidth

    ColorUtils {
        id: colorUtils
    }

    // Wave phase driving the strand motion below - advancing this is
    // mathematically identical to what the old Canvas did every repaint,
    // but here it just feeds reactive property bindings on PathPolyline.path,
    // which Qt Quick's scene graph re-triangulates and re-renders on the
    // GPU automatically. No manual repaint calls needed (unlike Canvas,
    // where `onExtentChanged: canvas.requestPaint()` used to be required
    // to force a clearing redraw on retract).
    property real wavePhase: 0
    Timer {
        interval: 33
        repeat: true
        running: root.active || root.extent > 0
        onTriggered: root.wavePhase += 0.1
    }

    // Same point math as the old Canvas onPaint loop, just returning a
    // point array for PathPolyline instead of driving ctx.lineTo() calls.
    function strandPoints(s, midY) {
        if (root.extent <= 0) return []
        const phaseOffset = s * 1.05
        const speedFactor = 1 + s * 0.08
        const baseAmplitude = 8 + (s % 3) * 4
        const wavelength = 11 + s * 1
        const pts = []
        for (let t = 0; t <= root.extent; t += 3) {
            const px = root.isLeft ? t : root.panelWidth - t
            const ramp = Math.min(1, t / 20, (root.extent - t) / 20) * root.pinchScale(px)
            const amplitude = root.amplitudeAt ? root.amplitudeAt(px, s) : baseAmplitude
            const y = midY + amplitude * ramp * Math.sin(t / wavelength + root.wavePhase * speedFactor + phaseOffset)
            pts.push(Qt.point(px, y))
        }
        return pts
    }

    // Both Repeaters below used to call strandPoints() for the same index,
    // computing every array twice per frame. Computed once here instead, on
    // each phase tick, and read from the cache by both.
    property var strandCache: []
    property var coreCache: []

    function rebuildStrands() {
        const midY = waveShape.height / 2
        const next = []
        for (let s = 0; s < waveShape.strandCount; s++) next.push(strandPoints(s, midY))
        strandCache = next
        coreCache = corePoints(midY)
    }

    onWavePhaseChanged: rebuildStrands()
    onAmplitudeAtChanged: rebuildStrands()
    // The band's silhouette depends on where the beam has reached and where
    // the modules are - not on the wave phase. Rebuilding it on every phase
    // tick re-triangulated a ~900-point polygon 30 times a second and cost
    // more than everything else in the bar put together.
    onExtentChanged: { rebuildStrands(); rebuildBand(); }
    onPinchSpansChanged: { rebuildStrands(); rebuildBand(); }
    onPanelWidthChanged: rebuildBand()
    Component.onCompleted: { rebuildStrands(); rebuildBand(); }

    function corePoints(midY) {
        if (root.extent <= 0) return []
        const pts = []
        for (let t = 0; t <= root.extent; t += 3) {
            const px = root.isLeft ? t : root.panelWidth - t
            const ramp = Math.min(1, t / 20, (root.extent - t) / 20)
            const y = midY + 1.5 * ramp * Math.sin(t / 12 + root.wavePhase * 1.2)
            pts.push(Qt.point(px, y))
        }
        return pts
    }

    // Same hex-string colors as before, just with an independently
    // adjustable alpha channel (like ctx.globalAlpha used to give us) since
    // ShapePath.strokeColor bakes its own alpha in.
    function alphaColor(hexColor, alpha) {
        const c = Qt.color(hexColor)
        return Qt.rgba(c.r, c.g, c.b, alpha)
    }

    // Idle "neon hum": a slow, gentle opacity drift while the bar is shown.
    // Left/right run at slightly different speeds so the two sides drift
    // out of phase instead of pulsing in lockstep.
    property real hum: 1.0
    SequentialAnimation on hum {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.7; duration: root.isLeft ? 1400 : 1700; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.7; to: 1.0; duration: root.isLeft ? 1400 : 1700; easing.type: Easing.InOutSine }
    }

    // Ambient edge glow. Fixed size - never tracks `root.extent` - so its
    // blurred layer texture is rendered once by the scene graph and then
    // just reused; only `opacity` (active/hum) changes, which is a cheap
    // alpha composite, no re-blur. This used to be one Rectangle whose
    // width tracked `root.extent` directly: every frame of every
    // reveal/retract forced a GPU texture reallocation + full reblur, and
    // since this bar gets toggled on/off constantly, that per-toggle cost
    // is what actually made the bar laggy (the canvas waves below cost the
    // same regardless of toggle frequency - this didn't).
    Rectangle {
        anchors.left: root.isLeft ? parent.left : undefined
        anchors.right: root.isLeft ? undefined : parent.right
        y: root.beamY - height / 2
        height: 44
        width: 160
        color: root.accentColor
        opacity: (root.active ? 1.0 : 0.0) * root.hum
        Behavior on opacity { NumberAnimation { duration: 150 } }
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 34 }
    }

    // Travelling tip highlight, shaped by the funnel profile above: accent at
    // the screen edge running to white at the tip. The old version was a
    // plain rectangle with a second rectangle of black gradient laid over it
    // for vertical falloff; the silhouette does that job now, and the band
    // and the capsule outline finally share one shape.
    Shape {
        id: bandShape
        anchors.fill: parent
        antialiasing: true
        // GeometryRenderer, not CurveRenderer: this is a large filled polygon
        // of straight segments, so there are no curves for CurveRenderer to
        // antialias - it just rasterises the whole area per-pixel and costs
        // dearly for it.
        preferredRendererType: Shape.GeometryRenderer

        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillGradient: LinearGradient {
                x1: root.isLeft ? 0 : root.panelWidth
                y1: 0
                x2: root.isLeft ? root.extent : root.panelWidth - root.extent
                y2: 0
                GradientStop { position: 0.0; color: root.accentColor }
                GradientStop { position: 0.93; color: root.accentColor }
                GradientStop { position: 1.0; color: "#FFFFFF" }
            }
            PathPolyline { path: root.bandPoints }
        }
        opacity: root.hum
    }

    // Beam core: GPU-rendered wave strands. This used to be a Canvas, which
    // Qt Quick always rasterizes on the CPU into a framebuffer and then
    // uploads as a texture every single repaint, regardless of how little
    // changed or how few strands were drawn - measured at 110% CPU while
    // animating vs. 7% idle, on this machine, no matter how much the strand
    // count or draw-call count were trimmed. Shape/ShapePath instead
    // triangulates each strand's polyline (cheap CPU work for a plain line)
    // and lets the GPU rasterize it, so the redraw cost that was fixed
    // Canvas overhead no longer scales with panel width or repaint
    // frequency the same way.
    Shape {
        id: waveShape
        anchors.left: parent.left
        y: root.beamY - height / 2
        width: root.panelWidth
        height: 40

        readonly property color strandColor: root.alphaColor(colorUtils.lightenColor(root.accentColor, 0.6), 1.0)
        readonly property int strandCount: 5

        // Halo (wide, faint) passes first so the crisp core passes below
        // paint on top of them - same "fake glow via double stroke" trick
        // as before, just as two separate ShapePaths instead of two
        // ctx.stroke() calls over the same Canvas path.
        //
        // Repeater can only instantiate Item-typed delegates, and ShapePath
        // isn't an Item - using it directly as a Repeater delegate fails
        // silently (no strands render at all). The documented workaround:
        // wrap each ShapePath in an Item delegate and push it into the
        // Shape's `data` list by hand once the Item exists.
        Repeater {
            model: waveShape.strandCount
            Item {
                readonly property real baseAlpha: 0.85 + (index % 2) * 0.15
                property ShapePath shapePath: ShapePath {
                    strokeColor: Qt.rgba(waveShape.strandColor.r, waveShape.strandColor.g, waveShape.strandColor.b, baseAlpha * 0.22)
                    strokeWidth: 9
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: root.strandCache[index] || [] }
                }
                Component.onCompleted: waveShape.data.push(shapePath)
            }
        }
        Repeater {
            model: waveShape.strandCount
            Item {
                readonly property real baseAlpha: 0.85 + (index % 2) * 0.15
                property ShapePath shapePath: ShapePath {
                    strokeColor: Qt.rgba(waveShape.strandColor.r, waveShape.strandColor.g, waveShape.strandColor.b, baseAlpha)
                    strokeWidth: 4
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: root.strandCache[index] || [] }
                }
                Component.onCompleted: waveShape.data.push(shapePath)
            }
        }

        ShapePath {
            strokeColor: root.alphaColor("#EEEEEE", 0.25)
            strokeWidth: 8
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.coreCache }
        }
        ShapePath {
            strokeColor: root.alphaColor("#EEEEEE", 0.9)
            strokeWidth: 3
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.coreCache }
        }
    }
}
