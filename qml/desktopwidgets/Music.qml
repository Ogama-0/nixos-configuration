import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import "../common"

PanelWindow {
    id: root

    property var cavaValues: []

    // Both bound to the session's one MprisModel, in shell.qml - which player
    // is "the" player is a decision with memory, and the bar capsule has to
    // make the same one.
    property var activePlayer: null
    property string playerctlName: ""

    // Playing on the phone, through kdeconnect. Its audio is not on this
    // machine, so the wave runs off RemoteSpectrum instead of cava - and the
    // artist line carries the marker that says so.
    property bool remote: false
    property var remoteLevels: []

    // What the ring draws: this machine's real output, or the stand-in.
    readonly property var waveLevels: root.remote ? root.remoteLevels : root.cavaValues

    property bool deezerRunning: false

    Process {
        id: deezerCheckProc
        command: ["pgrep", "-x", "deezer-enhanced"]
        onExited: (exitCode, exitStatus) => {
            root.deezerRunning = (exitCode === 0)
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: deezerCheckProc.running = true
    }

    // quickshell's MprisPlayer.position is a locally-interpolated value that
    // only resyncs on a playback-status transition or a Seeked signal, neither
    // of which most players emit on Next()/Previous() -- so it goes stale across
    // a track skip. Poll the real value via playerctl instead.
    property real livePosition: 0

    readonly property string trackKey: root.activePlayer
        ? (root.activePlayer.trackTitle + "|" + root.activePlayer.trackArtist + "|" + root.activePlayer.trackAlbum)
        : ""

    property int trackDirection: 1
    property bool suppressCoverMorph: false

    function beginOutgoingSnapshot() {
        root.suppressCoverMorph = true
        coverProgressBehavior.enabled = false
        slideContainer.grabToImage(function(result) {
            outgoingSnapshot.source = result.url
            outgoingSnapshot.x = 0
            outgoingSnapshot.opacity = 1
            outgoingSnapshot.visible = true
            slideContainer.opacity = 0
            slideOutAnim.restart()
            stuckTransitionGuard.restart()
        })
    }

    // next()/previous() are fired optimistically before we know whether the
    // player can actually move to another track (e.g. at the end of a
    // playlist/album, Deezer just no-ops them). When that happens trackKey
    // never changes, onTrackKeyChanged never fires, and slideContainer is
    // left stuck at opacity 0 forever even though playback never stopped.
    // This timer detects that stuck case and reverts the transition.
    Timer {
        id: stuckTransitionGuard
        interval: 500
        onTriggered: {
            if (slideContainer.opacity === 1) return
            slideInAnim.stop()
            slideContainer.x = 0
            slideContainer.opacity = 1
            outgoingSnapshot.visible = false
            if (root.suppressCoverMorph) {
                root.suppressCoverMorph = false
                coverProgressBehavior.enabled = true
            }
        }
    }

    onTrackKeyChanged: {
        stuckTransitionGuard.stop()
        root.livePosition = 0
        root.shufflePalette()
        coverAlignAnim.stop()
        root.coverRotation = 0
        slideInAnim.stop()
        slideContainer.x = root.trackDirection * slideContainer.width
        slideContainer.opacity = 0
        slideInAnim.start()
    }

    readonly property string currentArtUrl: root.artUrl(root.activePlayer)

    onCurrentArtUrlChanged: {
        root.coverAccentColor = "@tempColor@"
        root.coverPalette = []
        if (!root.currentArtUrl) return
        coverColorProc.running = false
        coverColorProc.command = ["bash", "-c",
            "curl -sL \"$1\" | convert - -resize 100x100 -colors 6 +dither -format '%c' histogram:info:-",
            "bash", root.currentArtUrl]
        coverColorProc.running = true
    }

    // No repaint handlers on any of these any more. They used to each call
    // waveRing.requestPaint()/waveCanvas.requestPaint(); both are Shapes now,
    // so a colour change is an ordinary property binding the scene graph
    // picks up, and only the two geometry drivers (ringPhase, displayValues)
    // rebuild any points at all.
    property color coverAccentColor: "@tempColor@"

    property var coverPalette: []

    property real paletteAngle: 0

    // Advanced by the card's one 33ms tick (the artArea timer), NOT by a
    // NumberAnimation.
    //
    // It WAS a `NumberAnimation on ringPhase`, 0 to 2*PI over 7s. Under the
    // old Canvas that was harmless: every change just called requestPaint(),
    // and Canvas coalesces to at most one repaint per frame. Driving a Shape
    // it is not harmless at all - a NumberAnimation steps once per displayed
    // frame, so the nine rings were being rebuilt at 60Hz while every other
    // per-frame job in this file had been moved to 30. Measured live with a
    // track playing: 53.9% of a core on the GUI thread, against 20.1% once
    // the phase moved onto the shared tick. Same rotation speed either way -
    // 2*PI over 7s is 0.0296 per 33ms tick.
    //
    // The step is applied only while playing, so a paused card stops turning
    // but still gets its per-tick rebuild and settles its bars to zero.
    property real ringPhase: 0
    readonly property real ringPhaseStep: Math.PI * 2 * 33 / 7000

    readonly property bool isPlayingNow: root.activePlayer !== null && root.activePlayer.isPlaying
    onIsPlayingNowChanged: {
        if (root.isPlayingNow) root.cavaValues = []
        if (root.suppressCoverMorph) {
            root.suppressCoverMorph = false
            Qt.callLater(function() { coverProgressBehavior.enabled = true })
        }
        if (!root.isPlayingNow) {
            const target = Math.round(root.coverRotation / 360) * 360
            coverAlignAnim.stop()
            coverAlignAnim.to = target
            coverAlignAnim.start()
        }
    }
    property real coverProgress: root.isPlayingNow ? 0 : 1
    Behavior on coverProgress {
        id: coverProgressBehavior
        NumberAnimation { duration: 300; easing.type: Easing.InOutQuad }
    }

    property real coverRotation: 0

    // The slow spin of the cover art. 33ms, not 16: the whole card now runs
    // on one 30Hz beat (see RemoteSpectrum.qml, which has fed 30fps all
    // along), and the step is doubled to keep the same 18.75 deg/s.
    Timer {
        interval: 33
        repeat: true
        running: root.visible && root.isPlayingNow
        onTriggered: root.coverRotation += 0.62
    }

    NumberAnimation {
        id: coverAlignAnim
        target: root
        property: "coverRotation"
        duration: 300
        easing.type: Easing.OutQuad
    }

    readonly property real coverExpandedTopPadding: 24
    readonly property real coverNormalSize: 130
    readonly property real coverExpandedSize: Math.max(root.coverNormalSize, contentColumn.y + titleText.y - 6 - root.coverExpandedTopPadding)
    readonly property real coverNormalCenterY: contentColumn.y + artArea.y + artArea.height / 2
    readonly property real coverExpandedCenterY: root.coverExpandedTopPadding + root.coverExpandedSize / 2
    readonly property real coverNormalRadius: root.coverNormalSize / 2
    readonly property real coverExpandedRadius: 24

    readonly property real coverCenterX: cardBg.width / 2
    readonly property real coverSize: root.coverNormalSize + (root.coverExpandedSize - root.coverNormalSize) * root.coverProgress
    readonly property real coverCenterY: root.coverNormalCenterY + (root.coverExpandedCenterY - root.coverNormalCenterY) * root.coverProgress
    readonly property real coverRadius: root.coverNormalRadius + (root.coverExpandedRadius - root.coverNormalRadius) * root.coverProgress

    function shufflePalette() {
        if (root.coverPalette.length === 0) return
        const shuffled = root.coverPalette.slice()
        for (let i = shuffled.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1))
            const tmp = shuffled[i]
            shuffled[i] = shuffled[j]
            shuffled[j] = tmp
        }
        root.coverPalette = shuffled
        root.paletteAngle = Math.random() * Math.PI * 2
    }

    function vibrantColor(r, g, b) {
        r /= 255; g /= 255; b /= 255
        const max = Math.max(r, g, b), min = Math.min(r, g, b)
        const l = (max + min) / 2
        const d = max - min
        let h = 0, s = 0
        if (d !== 0) {
            s = d / (1 - Math.abs(2 * l - 1))
            if (max === r) h = ((g - b) / d) % 6
            else if (max === g) h = (b - r) / d + 2
            else h = (r - g) / d + 4
            h *= 60
            if (h < 0) h += 360
        }
        if (s < 0.08) {
            const gl = Math.min(Math.max(l, 0.12), 0.85)
            return Qt.hsla(0, 0, gl, 1)
        }

        s = Math.max(s, 0.7)
        const lc = Math.min(Math.max(l, 0.5), 0.72)
        return Qt.hsla(h / 360, s, lc, 1)
    }

    function artUrl(player) {
        if (!player) return ""
        if (player.trackArtUrl) return player.trackArtUrl
        const url = player.metadata ? (player.metadata["xesam:url"] || "") : ""
        if (url.startsWith("https://www.youtube.com/watch")) {
            const m = url.match(/[?&]v=([\w-]{11})/)
            return m ? `https://img.youtube.com/vi/${m[1]}/hqdefault.jpg` : ""
        }
        return ""
    }

    function formatTime(sec) {
        if (!sec || sec < 0 || !isFinite(sec)) return "0:00"
        const total = Math.floor(sec)
        const m = Math.floor(total / 60)
        const s = total % 60
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    anchors {
        top: true
        right: true
    }
    margins {
        top: 280
        right: 24
    }

    implicitWidth: 440
    implicitHeight: 400
    color: "transparent"
    // deezerRunning gates the card on the desktop app being open - it is a
    // wallpaper widget, not a notification. A phone track over kdeconnect
    // has no local app to be open, so it counts on its own; otherwise the
    // remote wave and its marker would only ever appear on the bar.
    visible: root.activePlayer !== null && (root.deezerRunning || root.remote)

    // Every per-frame tick in this file is gated on `visible`, so when the
    // card goes away the wave stops wherever it happened to be. Clear it, or
    // the next time the card appears it pops in showing the last frame of
    // some track that finished hours ago and only then starts animating.
    // Empty rather than zeroed: the interpolator treats a length change as a
    // fresh start and snaps, which is what is wanted here.
    onVisibleChanged: if (!root.visible) artArea.displayValues = []

    WlrLayershell.namespace: "music-widget"
    WlrLayershell.layer: WlrLayer.Background

    Process {
        id: cavaProc
        // Not while the phone is playing: cava would be reading this
        // machine's silence, at 60fps, for a wave that already has a feed.
        running: root.activePlayer !== null && root.activePlayer.isPlaying && !root.remote
        command: ["cava", "-p", Quickshell.shellDir + "/cava.conf"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const parts = data.split(";").filter(s => s.length > 0).map(Number)
                if (parts.length > 0) root.cavaValues = parts
            }
        }
    }

    Process {
        id: coverColorProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const re = /(\d+):\s*\([^)]*\)\s*#([0-9A-Fa-f]{6})/g
                const found = []
                let m
                while ((m = re.exec(this.text)) !== null) {
                    found.push({ count: parseInt(m[1]), hex: m[2] })
                }
                if (found.length === 0) return

                found.sort((a, b) => b.count - a.count)
                const palette = found.slice(0, 4).map(c => {
                    const r = parseInt(c.hex.substring(0, 2), 16)
                    const g = parseInt(c.hex.substring(2, 4), 16)
                    const b = parseInt(c.hex.substring(4, 6), 16)
                    return root.vibrantColor(r, g, b)
                })

                root.coverPalette = palette
                root.coverAccentColor = palette[0]
                root.shufflePalette()
            }
        }
    }

    Process {
        id: positionProc
        running: false
        // -p, or playerctl answers for whichever player it likes best - with
        // a phone on the bus through kdeconnect that is a position from a
        // different song entirely.
        command: ["playerctl", "-p", root.playerctlName, "position"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(this.text)
                if (!isNaN(v)) root.livePosition = v
            }
        }
    }

    Timer {
        interval: 500
        running: root.activePlayer !== null && root.activePlayer.isPlaying
        repeat: true
        triggeredOnStart: true
        onTriggered: positionProc.running = true
    }

    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: 40
        color: "@cardBg@"
        border.color: "@cardBorder@"
        border.width: 2
        clip: true

        Item {
            id: slideContainer
            y: 0
            width: parent.width
            height: parent.height

        // Nine concentric wobbling rings behind the cover art, stroked with
        // the cover's own palette swept across them.
        //
        // This was a `Canvas` with `renderStrategy: Canvas.Immediate`, and it
        // was the single most expensive thing in the whole shell. Measured on
        // the live daemon: removing just this canvas's two repaint drivers
        // took the process from 161% of a core to 35%, and the eight Qt pool
        // threads from ~10% each to ~0.6%. One canvas, ~126% of a core -
        // Qt rasterises it with QPainter on the GUI thread and re-uploads the
        // whole texture on every repaint, 60 times a second, and that thread
        // is the one running every binding, timer and animation in the shell.
        // That is what "the bar feels laggy" was.
        //
        // The port follows BeamSide.qml, which made exactly this move for
        // exactly this reason - read its comments. Points are computed once
        // per tick into `ringCache` and handed to `PathPolyline`; the scene
        // graph re-triangulates and the GPU rasterises, with no manual
        // repaint call anywhere.
        //
        // Two things forced the shape of this:
        //
        //   * Rings are FILLED BANDS, not stroked lines. `ShapePath` has
        //     `fillGradient` but no stroke gradient, and the palette sweep
        //     across the rings is the whole look - a solid-coloured stroke
        //     would have been a visibly flatter widget. So each ring is an
        //     annulus: the centreline offset radially by `halfWidth` either
        //     way, outer edge forward then inner edge backward, closed. At
        //     2.4px wide a radial offset and a true normal differ by well
        //     under a pixel on a curve this gentle.
        //   * `Repeater` cannot have a `ShapePath` delegate - it needs an
        //     `Item`, and a `ShapePath` used directly renders nothing at all,
        //     silently (rule 4 in docs/adding-a-bar-widget.md). Each one is
        //     wrapped in an `Item` that pushes it into `Shape.data` by hand
        //     once it exists, which is BeamSide's documented workaround.
        //
        // Verified against a probe before being written: a `PathPolyline`
        // fed from a JS array rebuilt on a timer, a `LinearGradient` whose
        // endpoints and stops move at runtime, and both of those inside a
        // Repeater, all render correctly. Rule 4 only bites the delegate
        // case, which is why that one is wrapped.
        Shape {
            id: waveRing
            anchors {
                left: slideContainer.left
                right: slideContainer.right
                top: slideContainer.top
                leftMargin: 16
                rightMargin: 16
            }
            height: Math.max(0, contentColumn.y + titleText.y - 6)
            preferredRendererType: Shape.CurveRenderer

            // A Canvas rasterises into a buffer its own size, so anything
            // outside its width/height simply did not exist. A Shape has no
            // such bound - its ShapePaths draw wherever their coordinates
            // say, and the only thing stopping them is an ancestor that
            // clips. That difference is invisible most of the time and very
            // visible on PAUSE: the cover expands, this item's height
            // collapses, `cy` (height - 104) goes negative, and the ring
            // stack ends up centred above the card. The Canvas cropped it;
            // the first Shape version drew grey arcs across the top of the
            // card instead. Restoring the Canvas's implicit bound is the
            // whole fix.
            clip: true

            // Hidden once the wave has fully settled, which is what a paused
            // or stopped card looks like. The Canvas did this by accident -
            // with nothing driving requestPaint() while paused it simply left
            // an unpainted buffer - and the first Shape version, which has no
            // buffer to leave empty, drew the resting ring stack across the
            // top of the card instead. Nobody has ever seen that, so it is a
            // regression however defensible the geometry is.
            //
            // `displayValues` is emptied by the tick below the moment the
            // settle finishes, and is non-empty for the whole of playback and
            // the whole of the fade down, so this hides exactly at the end of
            // the animation and never during it. A silent passage mid-track
            // keeps the rings: that path only clears while NOT playing.
            visible: root.isPlayingNow || artArea.displayValues.length > 0

            // Every one of these is the number the Canvas used.
            readonly property int layerCount: 9
            readonly property real baseRadius: 76
            readonly property real amplitudeX: 32
            readonly property real amplitudeY: 10
            // ctx.lineWidth was 2.4, i.e. 1.2 either side of the centreline.
            readonly property real halfWidth: 1.2
            // Samples per original quadratic segment when flattening it into
            // a polyline, and this number was measured rather than guessed.
            // Against the Canvas it replaces (97.1% of a core on
            // tests/laserbar/music-card.qml, 15s, bar revealed):
            //
            //   3 -> 75.1%   indistinguishable from 2
            //   2 -> 64.9%   indistinguishable from the Canvas  <- this
            //   1 -> 47.1%   visibly polygonal, straight segments and corners
            //
            // Shape.GeometryRenderer is cheaper again (53.4% at 2) but does
            // not antialias these curves - the rings come out stair-stepped
            // next to the Canvas original, so it is not a trade worth taking.
            // `asynchronous: true` is far WORSE here, not better: 118.5%,
            // because the geometry is rebuilt 30 times a second and the
            // threaded path re-syncs on every one of them.
            readonly property int subdivisions: 2

            readonly property real cx: width / 2
            readonly property real cy: height - 104

            // Gradient endpoints, swept by paletteAngle exactly as
            // ctx.createLinearGradient's did. Colour only: these move without
            // touching ringCache, so a palette or angle change costs a
            // re-render and no geometry work at all. That is the main reason
            // the repaint handlers this file used to carry are gone.
            readonly property real gradSpan: Math.max(amplitudeX, amplitudeY) + baseRadius
            readonly property real gradX: Math.cos(root.paletteAngle) * gradSpan
            readonly property real gradY: Math.sin(root.paletteAngle) * gradSpan

            readonly property var palette: root.coverPalette.length > 0
                ? root.coverPalette
                : [root.coverAccentColor]

            // Four declared stops, because GradientStop is not an Item and so
            // cannot come out of a Repeater, while the palette is 1 to 4
            // colours. Short palettes collapse onto the end: two colours give
            // positions 0,1,1,1, which ramps once and then holds - the same
            // gradient the Canvas built from two stops.
            function stopPos(k) {
                const n = palette.length
                if (n <= 1) return k / 3
                return Math.min(k, n - 1) / (n - 1)
            }
            function stopColor(k, alpha) {
                const c = Qt.color(palette[Math.min(k, palette.length - 1)])
                return Qt.rgba(c.r, c.g, c.b, alpha)
            }

            // One array of band points per layer, rebuilt on a tick rather
            // than per consumer - the same reason BeamSide keeps a
            // strandCache instead of calling strandPoints() from both of its
            // Repeaters.
            property var ringCache: []

            function rebuildRings() {
                if (width <= 0 || height <= 0) { ringCache = []; return }

                const values = artArea.displayValues
                const bands = values.length > 0 ? values.length : 20
                const n = bands * 2
                const time = root.ringPhase

                // Mirrored band index, so the ring is symmetric left to
                // right the way the Canvas's was.
                const raw = []
                for (let i = 0; i < n; i++) {
                    const bandIndex = Math.min(i <= bands ? i : n - i, bands - 1)
                    raw.push((bandIndex < values.length ? values[bandIndex] : 0) / 100)
                }

                const out = []
                for (let l = 0; l < layerCount; l++) {
                    const layerT = l / (layerCount - 1)
                    const radiusOffset = (layerT - 0.5) * 26
                    const ampScale = 0.55 + layerT * 0.7
                    const phaseOffset = l * 0.9 + time * (0.4 + layerT * 0.6)

                    const pts = []
                    for (let i = 0; i < n; i++) {
                        const t = raw[i]
                        const angle = -Math.PI / 2 + (i / n) * Math.PI * 2
                        const wobble = t * 3 * Math.sin(angle * 3 + phaseOffset)
                        const rx = baseRadius + radiusOffset + t * amplitudeX * ampScale + wobble
                        const ry = baseRadius + radiusOffset + t * amplitudeY * ampScale + wobble * 0.4
                        pts.push({ x: cx + rx * Math.cos(angle), y: cy + ry * Math.sin(angle) })
                    }
                    out.push(bandFor(pts, n))
                }
                ringCache = out
            }

            // The Canvas drew quadratics THROUGH the midpoints of consecutive
            // points, using each point as the control handle. Same curve
            // here, just evaluated into vertices instead of handed to
            // ctx.quadraticCurveTo - and then offset either side of itself to
            // make the band.
            function bandFor(pts, n) {
                const outer = []
                const inner = []
                const sub = subdivisions
                for (let i = 0; i < n; i++) {
                    const cur = pts[i]
                    const prev = pts[(i - 1 + n) % n]
                    const next = pts[(i + 1) % n]
                    const p0x = (prev.x + cur.x) / 2
                    const p0y = (prev.y + cur.y) / 2
                    const p1x = (cur.x + next.x) / 2
                    const p1y = (cur.y + next.y) / 2
                    for (let s = 0; s < sub; s++) {
                        const t = s / sub
                        const u = 1 - t
                        const x = u * u * p0x + 2 * u * t * cur.x + t * t * p1x
                        const y = u * u * p0y + 2 * u * t * cur.y + t * t * p1y
                        // Radial normal. The rings are star-shaped about
                        // (cx, cy), so the outward direction is simply away
                        // from the centre; `len` can only be zero if a point
                        // lands exactly on the centre, which baseRadius 76
                        // rules out, but the guard costs nothing.
                        const dx = x - cx
                        const dy = y - cy
                        const len = Math.sqrt(dx * dx + dy * dy) || 1
                        const nx = dx / len * halfWidth
                        const ny = dy / len * halfWidth
                        outer.push(Qt.point(x + nx, y + ny))
                        inner.push(Qt.point(x - nx, y - ny))
                    }
                }
                // Close both loops back onto their own first sample before
                // joining them. Without this the polygon's closing chord cuts
                // straight across the band at 12 o'clock - i = 0 is the top,
                // because the angle starts at -PI/2 - and the render showed a
                // dark radial notch through all nine rings there. The
                // quadratic is periodic, so the first sample IS the last one.
                outer.push(outer[0])
                inner.push(inner[0])
                inner.reverse()
                return outer.concat(inner)
            }

            // Geometry only. Palette, accent and paletteAngle are bindings on
            // the gradient and deliberately do NOT appear here.
            onWidthChanged: rebuildRings()
            onHeightChanged: rebuildRings()
            Component.onCompleted: rebuildRings()


            Repeater {
                model: waveRing.layerCount
                Item {
                    required property int index
                    // The Canvas's per-layer globalAlpha: brightest in the
                    // middle of the stack, fading to the inner and outer
                    // edges. Baked into the gradient stops because a
                    // ShapePath has no opacity of its own to put it on.
                    readonly property real layerAlpha: {
                        const layerT = index / (waveRing.layerCount - 1)
                        return 0.4 + 0.5 * (1 - Math.abs(layerT - 0.5) * 2)
                    }
                    property ShapePath shapePath: ShapePath {
                        strokeColor: "transparent"
                        strokeWidth: 0
                        fillRule: ShapePath.OddEvenFill
                        fillGradient: LinearGradient {
                            x1: waveRing.cx - waveRing.gradX
                            y1: waveRing.cy - waveRing.gradY
                            x2: waveRing.cx + waveRing.gradX
                            y2: waveRing.cy + waveRing.gradY
                            GradientStop { position: 0.0; color: waveRing.stopColor(0, layerAlpha) }
                            GradientStop { position: waveRing.stopPos(1); color: waveRing.stopColor(1, layerAlpha) }
                            GradientStop { position: waveRing.stopPos(2); color: waveRing.stopColor(2, layerAlpha) }
                            GradientStop { position: 1.0; color: waveRing.stopColor(3, layerAlpha) }
                        }
                        PathPolyline { path: waveRing.ringCache[index] || [] }
                    }
                    Component.onCompleted: waveRing.data.push(shapePath)
                }
            }
        }

        ColumnLayout {
            id: contentColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 28
                rightMargin: 28
            }
            spacing: 10

            Item {
                id: artArea
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                implicitWidth: 200
                implicitHeight: 200
                clip: true

                property var displayValues: []

                // The card's ONE per-frame tick. Everything that moves at
                // 30Hz happens here and the rings are rebuilt exactly once
                // for all of it - the whole point, since the rebuild is the
                // expensive part and two drivers meant two rebuilds.
                //
                // Not gated on playback: it keeps running after a pause
                // precisely so the bars interpolate down to zero instead of
                // freezing at whatever height the last frame had. The gate is
                // `root.visible`.
                //
                // 33ms, not 16. Both feeds are already slower or equal to
                // that - RemoteSpectrum emits at 30fps by design and cava's
                // 60 is smoothed by this interpolation anyway - so the old
                // 16ms tick was re-deriving nine rings twice per input frame.
                Timer {
                    interval: 33
                    // Stops dead once the settle has finished, on the same
                    // condition that hides the rings - there is nothing left
                    // for it to do, and a visible paused card is a state that
                    // lasts hours. Playback resuming flips isPlayingNow and
                    // starts it again.
                    running: root.visible && root.activePlayer !== null
                             && (root.isPlayingNow || artArea.displayValues.length > 0)
                    repeat: true
                    onTriggered: {
                        const playing = root.activePlayer !== null && root.activePlayer.isPlaying

                        // Nothing is rebuilt unless something actually moved.
                        // A paused card that has finished settling is a real
                        // and common state - the track ends, or you pause and
                        // walk away - and it used to keep re-deriving nine
                        // identical rings 30 times a second for as long as
                        // the card was up. Measured: 26.3% of a core on a
                        // paused card, against ~3% once this flag gates it.
                        let moved = false

                        // The rotation. Only while playing, so a paused card
                        // holds still, and wrapped so the number cannot grow
                        // without bound over a long listening session.
                        if (playing) {
                            root.ringPhase = (root.ringPhase + root.ringPhaseStep) % (Math.PI * 2)
                            moved = true
                        }

                        const target = playing ? root.waveLevels : []
                        const n = playing ? target.length : artArea.displayValues.length
                        if (n > 0) {
                            if (artArea.displayValues.length !== n) {
                                artArea.displayValues = playing ? target.slice() : new Array(n).fill(0)
                                moved = true
                            } else {
                                // Half as many ticks than the old 16ms timer,
                                // so the per-tick fraction is the old one
                                // applied twice - 1-(1-f)^2 - and the rise and
                                // the settle take the same wall-clock time
                                // they did. Straight 0.55/0.09 here would have
                                // halved both speeds.
                                const factor = playing ? 0.80 : 0.17
                                const next = []
                                let peak = 0
                                for (let i = 0; i < n; i++) {
                                    const goal = playing ? target[i] : 0
                                    const v = artArea.displayValues[i] + (goal - artArea.displayValues[i]) * factor
                                    next.push(v)
                                    if (v > peak) peak = v
                                }
                                // The settle has to END, not merely approach
                                // zero: an exponential decay never reaches it,
                                // so without a floor the "finished" state below
                                // is never reached and the rebuild never stops.
                                // Half a unit on a 0-100 scale is a third of a
                                // pixel of bar height.
                                if (!playing && peak < 0.5) artArea.displayValues = []
                                else artArea.displayValues = next
                                moved = true
                            }
                        }

                        if (moved) waveRing.rebuildRings()
                    }
                }

            }

            Text {
                id: titleText
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.activePlayer ? root.activePlayer.trackTitle : "No media playing"
                color: "@clockColor@"
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }

            // The artist, with the remote marker beside it when the track
            // is the phone's. Centred as a pair: a Row inside a filling Item,
            // rather than a RowLayout, so the badge stays next to the name
            // instead of being pushed out to the card's edge.
            Item {
                id: artistLine
                Layout.fillWidth: true
                implicitHeight: artistRow.implicitHeight
                visible: root.activePlayer !== null

                Row {
                    id: artistRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 7

                    Text {
                        id: artistText
                        width: Math.min(implicitWidth,
                                        artistLine.width
                                        - (remoteBadge.visible ? remoteBadge.width + artistRow.spacing : 0))
                        elide: Text.ElideRight
                        text: root.activePlayer ? root.activePlayer.trackArtist : ""
                        color: "@dateColor@"
                        font.pixelSize: 16
                    }

                    RemoteBadge {
                        id: remoteBadge
                        anchors.verticalCenter: artistText.verticalCenter
                        visible: root.remote
                        tint: "@dateColor@"
                        glyphHeight: 13
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                Text {
                    text: root.formatTime(root.livePosition)
                    color: "@dateColor@"
                    font.pixelSize: 12
                }

                Item {
                    id: progressBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32

                    readonly property real progress: (root.activePlayer && root.activePlayer.length > 0)
                        ? Math.max(0, Math.min(1, root.livePosition / root.activePlayer.length))
                        : 0
                    property real wavePhase: 0

                    // Geometry drivers for the Shape below. No repaint calls:
                    // the strands are PathPolylines fed from this cache, so
                    // the scene graph redraws them on its own.
                    property var strandCache: []
                    property var trackCache: []

                    function rebuildWave() {
                        const midY = height / 2
                        const splitX = width * progress

                        // The unplayed remainder: a flat line from the
                        // playhead to the right edge. Two points, but kept in
                        // a cache like the rest so there is one rebuild path.
                        trackCache = splitX < width
                            ? [Qt.point(splitX, midY), Qt.point(width, midY)]
                            : []

                        const next = []
                        for (let s = 0; s < progressBar.strandCount; s++) {
                            const phaseOffset = s * 1.7
                            const speedFactor = 1 + s * 0.12
                            const amplitude = 5 + (s % 2) * 2
                            const wavelength = 6 + s * 1.3
                            const pts = []
                            for (let x = 0; x <= splitX; x += 2) {
                                const ramp = Math.min(1, x / 20, (splitX - x) / 20)
                                pts.push(Qt.point(x, midY + amplitude * ramp
                                    * Math.sin(x / wavelength + wavePhase * speedFactor + phaseOffset)))
                            }
                            next.push(pts)
                        }
                        strandCache = next
                    }

                    // Fixed at four so the Repeater's model never changes.
                    // The old Canvas picked min(4, max(3, palette.length))
                    // strands and indexed the palette modulo its length;
                    // strandColor() below keeps that mapping, and a strand
                    // the old code would not have drawn is simply given no
                    // points - the palette is 1-4 colours, so this only ever
                    // draws between three and four of them, same as before.
                    readonly property int strandCount: 4
                    readonly property int liveStrands: {
                        const n = root.coverPalette.length > 0 ? root.coverPalette.length : 1
                        return Math.min(4, Math.max(3, n))
                    }
                    function strandColor(s) {
                        const palette = root.coverPalette.length > 0
                            ? root.coverPalette
                            : [root.coverAccentColor]
                        const c = Qt.color(palette[s % palette.length])
                        return Qt.rgba(c.r, c.g, c.b, 0.85)
                    }

                    onProgressChanged: rebuildWave()
                    onWidthChanged: rebuildWave()
                    onHeightChanged: rebuildWave()
                    onWavePhaseChanged: rebuildWave()
                    Component.onCompleted: rebuildWave()

                    // 33ms with the step doubled, so the wave travels at the
                    // speed it always did on half the ticks. Gated on the
                    // card being visible as well as playing - see the
                    // ringPhase animation for why that matters on a
                    // background layer surface.
                    Timer {
                        interval: 33
                        repeat: true
                        running: root.visible && root.activePlayer !== null && root.activePlayer.isPlaying
                        onTriggered: progressBar.wavePhase += 0.1256
                    }

                    // Was a second Canvas.Immediate on the same 16ms tick as
                    // waveRing. Same port, and a much more direct one: these
                    // are plain solid-coloured polylines, which is exactly
                    // what BeamSide.qml's strands are.
                    Shape {
                        id: waveShape
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: "@dividerColor@"
                            strokeWidth: 2
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathPolyline { path: progressBar.trackCache }
                        }

                        Repeater {
                            model: progressBar.strandCount
                            Item {
                                required property int index
                                property ShapePath shapePath: ShapePath {
                                    strokeColor: index < progressBar.liveStrands
                                        ? progressBar.strandColor(index)
                                        : "transparent"
                                    strokeWidth: 2.2
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    joinStyle: ShapePath.RoundJoin
                                    PathPolyline { path: progressBar.strandCache[index] || [] }
                                }
                                Component.onCompleted: waveShape.data.push(shapePath)
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.activePlayer && root.activePlayer.canSeek
                        onClicked: mouse => {
                            if (root.activePlayer && root.activePlayer.length > 0) {
                                const target = Math.max(0, Math.min(1, mouse.x / width)) * root.activePlayer.length
                                root.activePlayer.position = target
                                root.livePosition = target
                            }
                        }
                    }
                }

                Text {
                    text: root.formatTime(root.activePlayer ? root.activePlayer.length : 0)
                    color: "@dateColor@"
                    font.pixelSize: 12
                }
            }

        }

        Rectangle {
            id: coverMask
            x: root.coverCenterX - width / 2
            y: root.coverCenterY - height / 2
            width: root.coverSize
            height: root.coverSize
            radius: root.coverRadius
            visible: false
            layer.enabled: true
        }

        Item {
            id: coverImg
            x: root.coverCenterX - width / 2
            y: root.coverCenterY - height / 2
            width: root.coverSize
            height: root.coverSize

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: coverMask
            }

            Item {
                id: coverSpinner
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                rotation: root.coverRotation

                Image {
                    id: coverPhoto
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: root.currentArtUrl
                }

                Item {
                    anchors.fill: parent
                    visible: coverPhoto.status !== Image.Ready

                    Rectangle {
                        anchors.fill: parent
                        color: "#161616"
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        radius: width / 2
                        color: "#1c1c1c"
                        border.color: "#2c2c2c"
                        border.width: 1
                    }

                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            anchors.centerIn: parent
                            width: parent.width * (0.86 - index * 0.15)
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.color: "#333333"
                            border.width: 1
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.32
                        height: width
                        radius: width / 2
                        color: root.coverAccentColor
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.05
                        height: width
                        radius: width / 2
                        color: "#0a0a0a"
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.activePlayer && root.activePlayer.canTogglePlaying
                onClicked: root.activePlayer.togglePlaying()
            }
        }

        Text {
            x: (root.coverCenterX - root.coverExpandedSize / 2) - 28 - width
            y: root.coverNormalCenterY - height / 2
            text: "❮"
            font.pixelSize: 28
            color: "@clockColor@"
            opacity: (root.activePlayer && root.activePlayer.canGoPrevious) ? 1.0 : 0.35

            MouseArea {
                anchors.centerIn: parent
                width: 44
                height: 44
                enabled: root.activePlayer && root.activePlayer.canGoPrevious
                onClicked: {
                    root.trackDirection = -1
                    root.beginOutgoingSnapshot()
                    root.activePlayer.previous()
                }
            }
        }

        Text {
            x: (root.coverCenterX + root.coverExpandedSize / 2) + 28
            y: root.coverNormalCenterY - height / 2
            text: "❯"
            font.pixelSize: 28
            color: "@clockColor@"
            opacity: (root.activePlayer && root.activePlayer.canGoNext) ? 1.0 : 0.35

            MouseArea {
                anchors.centerIn: parent
                width: 44
                height: 44
                enabled: root.activePlayer && root.activePlayer.canGoNext
                onClicked: {
                    root.trackDirection = 1
                    root.beginOutgoingSnapshot()
                    root.activePlayer.next()
                }
            }
        }
        }

        ParallelAnimation {
            id: slideInAnim
            NumberAnimation { target: slideContainer; property: "x"; to: 0; duration: 380; easing.type: Easing.OutCubic }
            NumberAnimation { target: slideContainer; property: "opacity"; to: 1; duration: 380; easing.type: Easing.OutCubic }
            onStopped: {
                if (root.suppressCoverMorph) {
                    root.suppressCoverMorph = false
                    coverProgressBehavior.enabled = true
                }
            }
        }

        Image {
            id: outgoingSnapshot
            x: 0
            y: 0
            width: cardBg.width
            height: cardBg.height
            visible: false
            smooth: true
            z: 10
        }

        SequentialAnimation {
            id: slideOutAnim
            ParallelAnimation {
                NumberAnimation { target: outgoingSnapshot; property: "x"; to: -root.trackDirection * cardBg.width; duration: 380; easing.type: Easing.InCubic }
                NumberAnimation { target: outgoingSnapshot; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InCubic }
            }
            PropertyAction { target: outgoingSnapshot; property: "visible"; value: false }
        }
    }
}
