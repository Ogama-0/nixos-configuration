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
        const amplitude = 8 + (s % 3) * 4
        const wavelength = 11 + s * 1
        const pts = []
        for (let t = 0; t <= root.extent; t += 3) {
            const px = root.isLeft ? t : root.panelWidth - t
            const ramp = Math.min(1, t / 20, (root.extent - t) / 20)
            const y = midY + amplitude * ramp * Math.sin(t / wavelength + root.wavePhase * speedFactor + phaseOffset)
            pts.push(Qt.point(px, y))
        }
        return pts
    }

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

    // Traveling tip highlight: accent-to-white gradient, resizes with
    // `root.extent` every animation frame.
    Rectangle {
        id: tipHighlight
        anchors.left: root.isLeft ? parent.left : undefined
        anchors.right: root.isLeft ? undefined : parent.right
        y: root.beamY - height / 2
        height: 44
        width: root.extent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: root.isLeft ? 0.0 : 1.0; color: root.accentColor }
            GradientStop { position: root.isLeft ? 0.95 : 0.05; color: root.accentColor }
            GradientStop { position: root.isLeft ? 1.0 : 0.0; color: "#FFFFFF" }
        }
        opacity: root.hum
    }

    // Vertical falloff for the highlight above: a plain black gradient
    // overlaid on top of it, opaque right at the top/bottom edges (hiding
    // the highlight completely there) and fading to fully transparent by
    // 5% height, continuing to fully clear by center - mirrored on the
    // bottom half. Pure alpha compositing, no layer/effect/texture-capture
    // involved, so there's nothing in this approach that can silently fail
    // the way MultiEffect.maskSource just did (twice).
    Rectangle {
        anchors.left: tipHighlight.left
        anchors.right: tipHighlight.right
        y: tipHighlight.y
        height: tipHighlight.height
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#E6000000" }
            GradientStop { position: 0.05; color: "#19000000" }
            GradientStop { position: 0.5; color: "#00000000" }
            GradientStop { position: 0.95; color: "#19000000" }
            GradientStop { position: 1.0; color: "#E6000000" }
        }
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
                    PathPolyline { path: root.strandPoints(index, waveShape.height / 2) }
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
                    PathPolyline { path: root.strandPoints(index, waveShape.height / 2) }
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
            PathPolyline { path: root.corePoints(waveShape.height / 2) }
        }
        ShapePath {
            strokeColor: root.alphaColor("#EEEEEE", 0.9)
            strokeWidth: 3
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.corePoints(waveShape.height / 2) }
        }
    }
}
