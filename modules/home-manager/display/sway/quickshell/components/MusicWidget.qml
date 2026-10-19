import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// The music widget, miniature: a spinning cover disc, a cava-driven wave,
// and the track title with its artist underneath.
//
// This is Music.qml's content shrunk onto the bar, not a second
// implementation of it - the player selection, the cava feed and the vinyl
// fallback art are the same ideas, reduced to what reads inside 38px of
// capsule. Three things had to change for the bar:
//
//   - No Canvas. Music.qml paints its ring and its progress wave with one;
//     on the bar that is a CPU rasterise and a texture upload per frame
//     (docs/adding-a-bar-widget.md, rule 3).
//   - The wave is built from Rectangles rather than a Shape. See the wave
//     section below - that is not a style choice.
//   - Nothing runs while the bar is down. cava, the smoothing tick and the
//     disc's rotation are all gated on `active`, so a held modifier is the
//     only thing that ever starts them. cava therefore starts cold on each
//     reveal and the wave swells over the first few frames rather than
//     being already at height; that is the deliberate trade against keeping
//     a spectrum analyser running all session for a bar nobody is looking
//     at.
//
// The play/pause state is shown on the disc's label. It is not clickable:
// the bar's PanelWindow takes no pointer input at all (`mask: Region {}`),
// and it is only on screen while the modifier is held, which is exactly
// when sway's floating_modifier owns the pointer.
Item {
    id: root

    // Read by BarGroup.
    property int pos: 1
    property bool groupWired: false
    // Bound by BarGroup.
    property bool active: false
    property real bodyHeight: 38
    property real uiScale: 1
    property color railColor: "@capsuleInk@"

    // The player, chosen the way Music.qml chooses it: whatever is playing,
    // else whatever is loaded but paused.
    readonly property var mprisPlayer: {
        const list = Mpris.players ? Mpris.players.values : []
        for (let i = 0; i < list.length; i++) {
            if (list[i].isPlaying) return list[i]
        }
        for (let i = 0; i < list.length; i++) {
            if (list[i].playbackState !== MprisPlaybackState.Stopped) return list[i]
        }
        return null
    }

    // Everything the widget draws comes through these five, defaulted off
    // Mpris. A render fixture assigns them directly, which replaces the
    // binding and needs no player on the bus.
    property bool hasPlayer: root.mprisPlayer !== null
    property bool playing: root.mprisPlayer !== null && root.mprisPlayer.isPlaying
    property string title: root.mprisPlayer ? root.mprisPlayer.trackTitle : ""
    property string artist: root.mprisPlayer ? root.mprisPlayer.trackArtist : ""
    property string artUrl: root.mprisPlayer ? root.artUrlFor(root.mprisPlayer) : ""

    // Raw cava bands, 0..100. A render fixture assigns these and clears
    // `cavaFeed`, which is the only reason that flag exists.
    property var levels: []
    property bool cavaFeed: true

    readonly property real discSize: 30 * uiScale
    readonly property real waveWidth: 42 * uiScale
    readonly property real waveHeight: 22 * uiScale
    readonly property real textWidth: 92 * uiScale

    readonly property real discX: 11 * uiScale
    readonly property real discPad: 3 * uiScale
    // What the cover's corners become when the music stops. Music.qml does
    // the same morph full size; here only the radius travels, because the
    // capsule is 38px tall and there is nowhere for the disc to grow into.
    readonly property real discSquareRadius: 7 * uiScale

    // 0 while playing, 1 while stopped. The disc carries the state on its
    // own - a record turning or a sleeve sitting still - so there is no
    // glyph over the artwork.
    property real pauseMorph: root.playing ? 0 : 1

    Behavior on pauseMorph {
        // Only while the bar is up. A track paused from a keyboard key with
        // the bar down would otherwise animate a mask texture and the
        // group's reveal layer for a third of a second, for nobody.
        enabled: root.active
        NumberAnimation { duration: 220; easing.type: Easing.InOutQuad }
    }
    readonly property real waveX: discX + discSize + 8 * uiScale
    readonly property real textX: waveX + waveWidth + 9 * uiScale

    // Collapses to nothing with no player, so the capsule is just the wifi
    // readout until something is playing.
    implicitWidth: hasPlayer ? textX + textWidth + 11 * uiScale : 0
    width: implicitWidth

    // Music.qml's trick for players that publish no art but do publish a
    // YouTube url.
    function artUrlFor(player) {
        if (!player) return ""
        if (player.trackArtUrl) return player.trackArtUrl
        const url = player.metadata ? (player.metadata["xesam:url"] || "") : ""
        if (url.startsWith("https://www.youtube.com/watch")) {
            const m = url.match(/[?&]v=([\w-]{11})/)
            return m ? `https://img.youtube.com/vi/${m[1]}/hqdefault.jpg` : ""
        }
        return ""
    }

    readonly property bool running: root.active && root.hasPlayer

    // The click target's two halves: whether the player will take the
    // request, and making it. A fixture with no player on the bus gets a
    // disabled button rather than a dead one.
    readonly property bool canToggle:
        root.mprisPlayer !== null && root.mprisPlayer.canTogglePlaying

    function togglePlay() {
        if (root.canToggle) root.mprisPlayer.togglePlaying()
    }

    Process {
        // One per bar, so one per screen on a multi-head setup - but only
        // while that bar is revealed.
        id: cavaProc
        running: root.cavaFeed && root.running && root.playing
        command: ["cava", "-p", Quickshell.shellDir + "/cava.conf"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                // isFinite, not just non-empty: one unparseable field in a
                // frame turns a band into NaN, the smoothing below carries
                // that NaN forward for the rest of the session, and a bar
                // whose opacity is NaN is simply not drawn - a wave that
                // vanishes for good on one malformed read.
                const parts = data.split(";")
                    .filter(s => s.length > 0)
                    .map(Number)
                    .filter(v => isFinite(v))
                if (parts.length > 0) root.levels = parts
            }
        }
    }

    // ── The wave ────────────────────────────────────────────────────
    //
    // Rectangles, not a Shape, and that is scar tissue rather than taste.
    //
    // A Shape here draws its path once and never again: a ShapePath whose
    // PathSvg or PathPolyline data comes from anything that changes - a
    // property written from JS, a function the binding calls, a point list
    // - renders nothing at all, with no warning and no error, while the
    // very same path written as a literal in QML renders fine. That was
    // checked from both ends: the generated path string, logged every
    // frame, was valid, and pasting one of those logged strings back in as
    // a literal drew it. BeamSide gets away with Shape because its strands
    // are built in a Repeater that pushes each ShapePath in by hand once
    // the data exists; a plain declarative ShapePath does not.
    //
    // Rectangles are what the rest of the bar animates (the workspace
    // strip's cells, the wifi bars) and they cost one node each.

    readonly property int waveBars: 11
    readonly property real waveBarWidth: 2.2 * uiScale
    readonly property real waveBarGap:
        (waveWidth - waveBars * waveBarWidth) / (waveBars - 1)
    // A bar is never a dot: at rest the wave is a flat line of stubs across
    // the middle, which is also what a paused track settles to.
    readonly property real waveBarMin: 2.2 * uiScale

    // Smoothed bands. cava's own output is smoothed in time already, but it
    // arrives at its framerate rather than ours, and a band that jumps
    // between two reads reads as a flicker at this size.
    property var displayLevels: []

    Timer {
        interval: 33
        repeat: true
        // Keeps ticking while paused so the bars fall back to the resting
        // line rather than freezing mid-height, then stops once they are
        // there.
        running: root.running && (root.playing || root.displayLevels.length > 0)
        onTriggered: {
            const target = root.playing ? root.levels : []
            const n = root.playing ? target.length : root.displayLevels.length
            if (n === 0) {
                root.displayLevels = []
                return
            }
            if (root.displayLevels.length !== n) {
                root.displayLevels = root.playing ? target.slice() : new Array(n).fill(0)
                return
            }
            const factor = root.playing ? 0.55 : 0.12
            const next = []
            let peak = 0
            for (let i = 0; i < n; i++) {
                const goal = root.playing ? target[i] : 0
                const v = root.displayLevels[i] + (goal - root.displayLevels[i]) * factor
                next.push(v)
                if (v > peak) peak = v
            }
            // Settled flat: stop rather than tick a dead wave forever.
            root.displayLevels = (!root.playing && peak < 0.5) ? [] : next
        }
    }

    // On hide: the bands are dropped so the next reveal starts from the
    // resting line instead of replaying whatever was playing last time,
    // and a stopped disc lands upright rather than waiting to be wound
    // back in front of someone.
    onActiveChanged: {
        if (root.active) return;
        root.displayLevels = [];
        if (!root.playing) {
            alignAnim.stop();
            spinner.rotation = 0;
        }
    }

    // cava's band count is its own; the wave has eleven bars whatever it
    // sends, so each bar averages the slice of the spectrum under it.
    function bandLevel(i) {
        const values = root.displayLevels
        if (!values || values.length === 0) return 0
        const from = Math.floor(i * values.length / root.waveBars)
        const to = Math.max(from + 1, Math.floor((i + 1) * values.length / root.waveBars))
        let sum = 0
        let count = 0
        for (let j = from; j < to && j < values.length; j++) {
            if (!isFinite(values[j])) continue
            sum += values[j]
            count++
        }
        if (count === 0) return 0
        return Math.max(0, Math.min(1, sum / count / 100))
    }

    // ── The disc ────────────────────────────────────────────────────
    //
    // Also the play/pause control. The button is a few pixels wider than
    // the disc so its hover ring is visible around it - a highlight
    // exactly under an opaque cover would never be seen.
    BarButton {
        id: discButton

        x: root.discX - root.discPad
        y: (root.bodyHeight - height) / 2
        width: root.discSize + 2 * root.discPad
        height: width
        visible: root.hasPlayer
        enabled: root.canToggle
        tint: root.railColor
        // The highlight keeps the cover's own corners as it morphs, so a
        // paused sleeve does not sit inside a circular glow.
        plateRadius: discMask.radius + root.discPad
        onClicked: root.togglePlay()

        Item {
            id: disc
            anchors.centerIn: parent
            width: root.discSize
            height: root.discSize

            // The mask is a texture, rendered at the item's own size, and
            // a 30px circle comes out as a visible octagon - the cover
            // looked like a stop sign on the real bar. Rendering the mask
            // at 4x and letting it scale down is what makes the edge
            // round; antialiasing and samples alone did nothing.
            Rectangle {
                id: discMask
                anchors.fill: parent
                radius: width / 2 + (root.discSquareRadius - width / 2) * root.pauseMorph
                visible: false
                antialiasing: true
                layer.enabled: true
                layer.smooth: true
                layer.samples: 4
                layer.textureSize: Qt.size(Math.round(root.discSize * 4), Math.round(root.discSize * 4))
            }

            Item {
                anchors.fill: parent
                // Fixed size, so this layer's texture is allocated once - the
                // rule against layer.effect is about items that resize.
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: discMask
                }

                Item {
                    id: spinner
                    anchors.fill: parent

                    Image {
                        id: cover
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: Math.round(root.discSize)
                        sourceSize.height: Math.round(root.discSize)
                        source: root.artUrl
                    }

                    // Vinyl, for a player with no art. Rings alone are rotation
                    // symmetric and would look still, so there is a radial tick.
                    Item {
                        anchors.fill: parent
                        visible: cover.status !== Image.Ready

                        Rectangle {
                            anchors.fill: parent
                            // The same corners as the mask, so a paused
                            // track with no cover art is a sleeve too
                            // rather than a disc in a square hole.
                            radius: discMask.radius
                            color: "@capsuleInk@"
                            opacity: 0.85
                        }

                        Repeater {
                            model: 2

                            Rectangle {
                                required property int index

                                anchors.centerIn: parent
                                width: parent.width * (0.82 - index * 0.22)
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: "@capsuleFill@"
                                border.width: Math.max(1, 0.8 * root.uiScale)
                                opacity: 0.35
                            }
                        }

                        Rectangle {
                            x: parent.width / 2
                            y: parent.height / 2 - height / 2
                            width: parent.width * 0.44
                            height: Math.max(1, 0.9 * root.uiScale)
                            color: "@capsuleFill@"
                            opacity: 0.4
                        }
                    }
                }
            }

        }
    }

    // Rotation of the disc. A NumberAnimation rather than Music.qml's 16ms
    // JS timer: the animation system drives it without a script call per
    // frame, and it stops with the reveal.
    NumberAnimation {
        id: spinAnim
        target: spinner
        property: "rotation"
        from: 0
        to: 360
        duration: 7000
        loops: Animation.Infinite
        running: root.running && root.playing
    }

    // Stopping mid-turn leaves the artwork askew, and a sleeve that sits
    // crooked reads as a glitch rather than a pause. Wind it back to
    // upright, the way Music.qml aligns its cover.
    NumberAnimation {
        id: alignAnim
        target: spinner
        property: "rotation"
        to: 0
        duration: 260
        easing.type: Easing.OutQuad
    }

    onPlayingChanged: {
        if (root.playing) return;
        // `running` is bound to `playing`, so the spin has already given up
        // the property by the time this runs.
        if (root.active) alignAnim.restart();
        else spinner.rotation = 0;
    }


    Repeater {
        model: root.hasPlayer ? root.waveBars : 0

        Rectangle {
            required property int index

            readonly property real level: {
                // Naming displayLevels here is what makes each bar re-read
                // its slice of the spectrum on every tick.
                root.displayLevels;
                return root.bandLevel(index);
            }

            x: root.waveX + index * (root.waveBarWidth + root.waveBarGap)
            width: root.waveBarWidth
            height: root.waveBarMin + level * (root.waveHeight - root.waveBarMin)
            y: (root.bodyHeight - height) / 2
            radius: width / 2
            color: root.railColor
            // The quiet bars sit back so the loud ones carry the shape.
            opacity: 0.45 + 0.55 * level
        }
    }

    // ── Title, artist underneath ────────────────────────────────────
    Column {
        x: root.textX
        width: root.textWidth
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasPlayer
        spacing: 1 * root.uiScale

        Text {
            width: parent.width
            text: root.title !== "" ? root.title : "unknown track"
            color: "@capsuleInk@"
            font.family: "Orbitron"
            font.pixelSize: Math.round(11 * root.uiScale)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: root.artist
            visible: root.artist !== ""
            color: "@capsuleInk@"
            opacity: 0.6
            font.family: "Orbitron"
            font.pixelSize: Math.round(9 * root.uiScale)
            elide: Text.ElideRight
        }
    }
}
