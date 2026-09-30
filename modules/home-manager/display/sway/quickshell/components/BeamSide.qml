import QtQuick
import QtQuick.Effects
import "colorUtils.js" as ColorUtils

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

    Rectangle {
        anchors.left: root.isLeft ? parent.left : undefined
        anchors.right: root.isLeft ? undefined : parent.right
        y: root.beamY - height / 2
        height: 54
        width: root.extent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: root.isLeft ? 0.0 : 1.0; color: root.accentColor }
            GradientStop { position: root.isLeft ? 0.95 : 0.05; color: root.accentColor }
            GradientStop { position: root.isLeft ? 1.0 : 0.0; color: "#FFFFFF" }
        }
        opacity: 0.42 * root.hum
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 34 }
    }

    Rectangle {
        anchors.left: root.isLeft ? parent.left : undefined
        anchors.right: root.isLeft ? undefined : parent.right
        y: root.beamY - height / 2
        height: 42
        width: root.extent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: root.isLeft ? 0.0 : 1.0; color: root.accentColor }
            GradientStop { position: root.isLeft ? 0.95 : 0.05; color: root.accentColor }
            GradientStop { position: root.isLeft ? 1.0 : 0.0; color: "#FFFFFF" }
        }
        opacity: 0.68 * root.hum
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 18 }
    }

    Rectangle {
        anchors.left: root.isLeft ? parent.left : undefined
        anchors.right: root.isLeft ? undefined : parent.right
        y: root.beamY - height / 2
        height: 34
        width: root.extent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: root.isLeft ? 0.0 : 1.0; color: root.accentColor }
            GradientStop { position: root.isLeft ? 0.95 : 0.05; color: root.accentColor }
            GradientStop { position: root.isLeft ? 1.0 : 0.0; color: "#FFFFFF" }
        }
        opacity: 1.0 * root.hum
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 9 }
    }

    // Beam core. Fixed full-width and always left-anchored regardless of
    // `side` - resizing a Canvas reallocates its backing texture, and
    // animating its width directly (tracking the Behavior-animated extent)
    // made the reveal/retract travel choppy: a reallocation on every single
    // frame of that 150ms animation. The draw loop below still tracks the
    // live extent each frame; only the canvas's own size/position are
    // constant. `t` is distance-from-source (0 = screen edge, extent = the
    // meeting tip) for both sides; `px` maps that to the actual canvas
    // x-coordinate, which is what differs between the two sides.
    Canvas {
        id: canvas
        anchors.left: parent.left
        y: root.beamY - height / 2
        width: root.panelWidth
        height: 40
        renderStrategy: Canvas.Immediate

        property real wavePhase: 0

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const midY = height / 2
            const extent = root.extent
            if (extent <= 0) return

            const strandCount = 3
            for (let s = 0; s < strandCount; s++) {
                const phaseOffset = s * 1.05
                const speedFactor = 1 + s * 0.08
                const amplitude = 8 + (s % 3) * 4
                const wavelength = 6 + s * 0.5

                ctx.strokeStyle = ColorUtils.lightenColor(root.accentColor, 0.6)
                ctx.lineWidth = 2.2
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.globalAlpha = 0.85 + (s % 2) * 0.15
                ctx.beginPath()
                for (let t = 0; t <= extent; t += 3) {
                    const px = root.isLeft ? t : width - t
                    const ramp = Math.min(1, t / 20, (extent - t) / 20)
                    const y = midY + amplitude * ramp * Math.sin(t / wavelength + canvas.wavePhase * speedFactor + phaseOffset)
                    if (t === 0) ctx.moveTo(px, y)
                    else ctx.lineTo(px, y)
                }
                ctx.stroke()
            }

            ctx.strokeStyle = "#EEEEEE"
            ctx.lineWidth = 3
            ctx.globalAlpha = 0.9
            ctx.beginPath()
            for (let t = 0; t <= extent; t += 3) {
                const px = root.isLeft ? t : width - t
                const ramp = Math.min(1, t / 20, (extent - t) / 20)
                const y = midY + 1.5 * ramp * Math.sin(t / 12 + canvas.wavePhase * 1.2)
                if (t === 0) ctx.moveTo(px, y)
                else ctx.lineTo(px, y)
            }
            ctx.stroke()
            ctx.globalAlpha = 1
        }

        // Stays running through the retract (not just while active) so the
        // wave keeps repainting - and thus visibly shrinking - in step with
        // the glow instead of freezing mid-animation the instant `active`
        // flips false.
        Timer {
            interval: 33
            repeat: true
            running: root.active || root.extent > 0
            onTriggered: canvas.wavePhase += 0.1
        }

        onWavePhaseChanged: requestPaint()
    }
}
