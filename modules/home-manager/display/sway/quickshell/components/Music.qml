import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

PanelWindow {
    id: root

    property var cavaValues: []

    property var activePlayer: {
        const list = Mpris.players.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].isPlaying) return list[i]
        }
        for (let i = 0; i < list.length; i++) {
            if (list[i].playbackState !== MprisPlaybackState.Stopped) return list[i]
        }
        return null
    }

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
        })
    }

    onTrackKeyChanged: {
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

    property color coverAccentColor: "@tempColor@"
    onCoverAccentColorChanged: waveRing.requestPaint()

    property var coverPalette: []
    onCoverPaletteChanged: {
        waveRing.requestPaint()
        waveCanvas.requestPaint()
    }

    property real paletteAngle: 0
    onPaletteAngleChanged: waveRing.requestPaint()

    property real ringPhase: 0
    onRingPhaseChanged: waveRing.requestPaint()
    NumberAnimation on ringPhase {
        from: 0
        to: Math.PI * 2
        duration: 7000
        loops: Animation.Infinite
        running: root.activePlayer !== null && root.activePlayer.isPlaying
    }

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

    Timer {
        interval: 16
        repeat: true
        running: root.isPlayingNow
        onTriggered: root.coverRotation += 0.3
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
    visible: root.activePlayer !== null && root.deezerRunning

    WlrLayershell.namespace: "music-widget"
    WlrLayershell.layer: WlrLayer.Background

    Process {
        id: cavaProc
        running: root.activePlayer !== null && root.activePlayer.isPlaying
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
        command: ["playerctl", "position"]
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

        Canvas {
            id: waveRing
            anchors {
                left: slideContainer.left
                right: slideContainer.right
                top: slideContainer.top
                leftMargin: 16
                rightMargin: 16
            }
            height: Math.max(0, contentColumn.y + titleText.y - 6)
            antialiasing: true
            renderStrategy: Canvas.Immediate

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                const values = artArea.displayValues
                const bands = values.length > 0 ? values.length : 20
                const n = bands * 2
                const cx = width / 2
                const cy = height - 104
                const baseRadius = 76
                const amplitudeX = 32
                const amplitudeY = 10
                const time = root.ringPhase

                const raw = []
                for (let i = 0; i < n; i++) {
                    const bandIndex = Math.min(i <= bands ? i : n - i, bands - 1)
                    const value = bandIndex < values.length ? values[bandIndex] : 0
                    raw.push(value / 100)
                }

                function midpoint(a, b) {
                    return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }
                }

                const span = Math.max(amplitudeX, amplitudeY) + baseRadius
                const dx = Math.cos(root.paletteAngle) * span
                const dy = Math.sin(root.paletteAngle) * span
                const grad = ctx.createLinearGradient(cx - dx, cy - dy, cx + dx, cy + dy)
                const palette = root.coverPalette.length > 0 ? root.coverPalette : [root.coverAccentColor]
                for (let p = 0; p < palette.length; p++) {
                    const stop = palette.length === 1 ? 0 : p / (palette.length - 1)
                    grad.addColorStop(stop, palette[p])
                }

                const layerCount = 9
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

                    ctx.beginPath()
                    let m = midpoint(pts[n - 1], pts[0])
                    ctx.moveTo(m.x, m.y)
                    for (let i = 0; i < n; i++) {
                        const next = pts[(i + 1) % n]
                        const mid = midpoint(pts[i], next)
                        ctx.quadraticCurveTo(pts[i].x, pts[i].y, mid.x, mid.y)
                    }
                    ctx.closePath()

                    ctx.lineWidth = 2.4
                    ctx.lineJoin = "round"
                    ctx.strokeStyle = grad
                    ctx.globalAlpha = 0.4 + 0.5 * (1 - Math.abs(layerT - 0.5) * 2)
                    ctx.stroke()
                }
                ctx.globalAlpha = 1
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

                Timer {
                    interval: 16
                    running: root.activePlayer !== null
                    repeat: true
                    onTriggered: {
                        const playing = root.activePlayer !== null && root.activePlayer.isPlaying
                        const target = playing ? root.cavaValues : []
                        const n = playing ? target.length : artArea.displayValues.length
                        if (n === 0) return
                        if (artArea.displayValues.length !== n) {
                            artArea.displayValues = playing ? target.slice() : new Array(n).fill(0)
                        } else {
                            const factor = playing ? 0.55 : 0.09
                            const next = []
                            for (let i = 0; i < n; i++) {
                                const goal = playing ? target[i] : 0
                                next.push(artArea.displayValues[i] + (goal - artArea.displayValues[i]) * factor)
                            }
                            artArea.displayValues = next
                        }
                    }
                }

                onDisplayValuesChanged: waveRing.requestPaint()
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

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: root.activePlayer !== null
                text: root.activePlayer ? root.activePlayer.trackArtist : ""
                color: "@dateColor@"
                font.pixelSize: 16
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

                    onProgressChanged: waveCanvas.requestPaint()
                    onWidthChanged: waveCanvas.requestPaint()
                    onWavePhaseChanged: waveCanvas.requestPaint()

                    Timer {
                        interval: 16
                        repeat: true
                        running: root.activePlayer !== null && root.activePlayer.isPlaying
                        onTriggered: progressBar.wavePhase += 0.0628
                    }

                    Canvas {
                        id: waveCanvas
                        anchors.fill: parent
                        renderStrategy: Canvas.Immediate

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            const midY = height / 2
                            const splitX = width * progressBar.progress

                            ctx.strokeStyle = "@dividerColor@"
                            ctx.lineWidth = 2
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            ctx.moveTo(splitX, midY)
                            ctx.lineTo(width, midY)
                            ctx.stroke()

                            const palette = root.coverPalette.length > 0 ? root.coverPalette : [root.coverAccentColor]
                            const strandCount = Math.min(4, Math.max(3, palette.length))
                            for (let s = 0; s < strandCount; s++) {
                                const color = palette[s % palette.length]
                                const phaseOffset = s * 1.7
                                const speedFactor = 1 + s * 0.12
                                const amplitude = 5 + (s % 2) * 2
                                const wavelength = 6 + s * 1.3

                                ctx.strokeStyle = color
                                ctx.lineWidth = 2.2
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"
                                ctx.globalAlpha = 0.85
                                ctx.beginPath()
                                for (let x = 0; x <= splitX; x += 2) {
                                    const ramp = Math.min(1, x / 20, (splitX - x) / 20)
                                    const y = midY + amplitude * ramp * Math.sin(x / wavelength + progressBar.wavePhase * speedFactor + phaseOffset)
                                    if (x === 0) ctx.moveTo(x, y)
                                    else ctx.lineTo(x, y)
                                }
                                ctx.stroke()
                            }

                            ctx.globalAlpha = 1
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
