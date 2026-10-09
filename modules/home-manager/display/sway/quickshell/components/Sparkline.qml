import QtQuick

// One service's recent probe history: a latency line with failed probes
// marked as vertical ticks. Canvas rather than Shape (which BeamSide.qml
// moved to for performance) because this repaints on a 10s poll, not per
// frame - the Canvas cost is irrelevant here and the imperative path is far
// clearer for a polyline plus ticks.
Canvas {
    id: root

    // Array of { success: bool, ms: real }, oldest first.
    property var history: []

    // Gatus keeps 50 results per endpoint. Drawn across 46px that is 0.94px
    // per point, which merges adjacent 2.8px failure ticks into one block and
    // makes a single failure read as several. The most recent slice is also
    // the part worth seeing.
    readonly property int maxPoints: 16
    readonly property var points: history.length > maxPoints
        ? history.slice(history.length - maxPoints) : history
    property color lineColor: "@upColor@"
    property color failColor: "@downColor@"

    // Per-row adaptive scale. A fixed ceiling does not work here: measured
    // latencies on oserv run 0.1ms (Samba, a TCP connect) to 35ms (Grafana),
    // so any ceiling high enough to show a 400ms degradation flattens every
    // healthy row onto the baseline - 0.63px of travel on a 13px canvas.
    //
    // The floor stops the opposite failure: Samba's 0.1-0.7ms jitter would
    // otherwise autoscale into dramatic-looking swings. Below the floor a row
    // reads as flat, which is the honest description of "fast and steady",
    // while a genuine 50x regression still clears it and shows up.
    //
    // Failed probes are excluded from the max: a timeout reports the full
    // --max-time as its duration, and letting that set the ceiling would
    // crush all the real measurements against the baseline.
    readonly property real msFloor: 12
    readonly property real msCeiling: {
        let peak = 0
        for (let i = 0; i < points.length; i++) {
            if (points[i].success && points[i].ms > peak)
                peak = points[i].ms
        }
        return Math.max(msFloor, peak * 1.15)
    }

    implicitWidth: 46
    implicitHeight: 13
    renderStrategy: Canvas.Immediate

    onPointsChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onMsCeilingChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()

        const n = points.length
        if (n === 0)
            return

        const step = n > 1 ? width / (n - 1) : 0

        // Failed probes first, so the line draws over them.
        ctx.fillStyle = root.failColor
        ctx.globalAlpha = 0.45
        for (let i = 0; i < n; i++) {
            if (points[i].success)
                continue
            ctx.fillRect(Math.max(0, i * step - 1.4), 0, 2.8, height)
        }

        if (n < 2)
            return

        ctx.globalAlpha = 0.85
        ctx.strokeStyle = root.lineColor
        ctx.lineWidth = 1.4
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.beginPath()

        for (let i = 0; i < n; i++) {
            const norm = Math.min(1, Math.max(0, points[i].ms / root.msCeiling))
            // A failure pins to the top of the band rather than to a latency
            // of zero, which would otherwise read as "instant".
            const y = points[i].success ? height - 2 - norm * (height - 5) : 1.5
            if (i === 0)
                ctx.moveTo(0, y)
            else
                ctx.lineTo(i * step, y)
        }

        ctx.stroke()
    }
}
