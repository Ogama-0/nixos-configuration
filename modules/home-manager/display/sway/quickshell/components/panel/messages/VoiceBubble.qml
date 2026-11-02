import QtQuick

// A voice note, played in place. Layout C of three mocked up for the spec:
// a round play/pause button, a wide seek bar with a handle, and the time on
// the right - no skip buttons here, ±5s lives on the arrow keys instead
// (that is Task 4's job, not this component's).
//
// One MessageAudio is shared by every bubble in the pane (see
// docs/messages-panel.md, "One player, not one per bubble"), so this
// component never owns playback state itself - it only asks "is `msgId` the
// one `audio` is doing right now" and draws accordingly. Tapping the button
// is the ONLY way in: it hands `audio.toggle()` the whole attachment record
// so a note with no local file yet raises the fetch, and one that does
// starts it, exactly as toggle()'s own three-way branch expects.
Item {
    id: root

    property real uiScale: 1
    property bool outgoing: false
    property var audio: null
    property string msgId: ""
    // {partId, mime, data, uid, path} - the same record MessagesModel
    // parses an attachment into. `path` is "" until a fetch lands.
    property var attachment: ({})
    // "Voice message" from the caller's mime switch - shown in the time
    // slot until a duration is known (see `timeText` below), which is more
    // honest than a fake "0:00" for a note nobody has opened yet.
    property string label: "Voice message"

    readonly property color ink: root.outgoing ? "@msgAccentInk@" : "@clockColor@"
    // The same 0.32-alpha-of-ink wash ConversationView's fallback recess
    // uses, at a lighter weight - this is a control sitting ON the bubble's
    // own fill, not a card of its own, and a heavier wash started reading as
    // a second bubble stacked on the first.
    readonly property color wash: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.22)

    readonly property bool isActive: root.audio !== null
        && root.audio.playingId === root.msgId
    readonly property bool isPlaying: root.isActive && !root.audio.paused
    // pendingMsgId, not pendingUid: it is the id this component compares
    // itself against everywhere else, and the two are set together (see
    // MessageAudio.toggle's no-path branch).
    readonly property bool isAwaitingMe: root.audio !== null
        && root.audio.awaiting && root.audio.pendingMsgId === root.msgId

    // The fetch timeout clears pendingMsgId in the SAME tick it sets
    // `missing` (MessageAudio.fetchTimer.onTriggered), so by the time
    // `missing` is readable nothing on `audio` says whose fetch it was.
    // `requestedFetch` is this bubble's own memory of having been the one
    // that asked - cleared the moment a DIFFERENT message becomes the
    // pending one, so a second note's timeout cannot relight this one's
    // missing state after `audio.missing` goes true again.
    property bool requestedFetch: false
    readonly property bool isMissingMe: root.audio !== null && root.audio.missing
        && root.requestedFetch && !root.isAwaitingMe && !root.isActive

    Connections {
        target: root.audio
        enabled: root.audio !== null
        function onPendingMsgIdChanged() {
            if (root.audio.pendingMsgId !== "" && root.audio.pendingMsgId !== root.msgId)
                root.requestedFetch = false;
        }
    }

    // What this bubble knew the one time it WAS playing, kept after
    // `audio` moves on to someone else - the real MediaPlayer only reports
    // duration once a source has actually loaded, so there is no way to
    // know it before the first play, and no reason to forget it after.
    property real knownDuration: 0
    Connections {
        target: root.audio
        enabled: root.audio !== null
        function onDurationChanged() {
            if (root.isActive && root.audio.duration > 0)
                root.knownDuration = root.audio.duration;
        }
    }

    // Written as a function body that reads `audio.position`/`duration`
    // UNCONDITIONALLY, not as a ternary - QML only tracks the properties an
    // expression actually touched on its LAST evaluation, and a ternary
    // that short-circuited past `audio.position` the first time (while
    // `isActive` was still false, at component creation) never registers
    // it as a dependency, so a later `position` update - the normal case,
    // it changes well after `playingId` does - would silently stop
    // reaching this bubble.
    readonly property real shownPosition: {
        const p = root.audio ? root.audio.position : 0;
        return root.isActive ? p : 0;
    }
    readonly property real shownDuration: {
        const d = root.audio ? root.audio.duration : 0;
        return root.isActive ? d : root.knownDuration;
    }
    readonly property real progress: root.audio
        ? root.audio.progressAt(root.shownPosition, root.shownDuration) : 0

    readonly property string timeText: {
        if (!root.audio) return root.label;
        const elapsed = root.audio.clock(root.shownPosition);
        if (root.isActive) return elapsed;
        return root.knownDuration > 0 ? root.audio.clock(root.knownDuration) : root.label;
    }

    function tapped(): void {
        if (!root.audio) return;
        const path = root.attachment.path || "";
        if (!path) root.requestedFetch = true;
        root.audio.toggle(root.msgId, path,
                           String(root.attachment.uid || ""),
                           root.attachment.partId || 0);
    }

    function seekAt(x: real): void {
        if (!root.audio || track.width <= 0) return;
        root.audio.seekTo(root.audio.duration * x / track.width);
    }

    // ---- the round button ----

    Rectangle {
        id: playButton
        anchors.verticalCenter: parent.verticalCenter
        x: 0
        width: parent.height
        height: parent.height
        radius: width / 2
        color: root.wash
    }

    // Drawn, not a font glyph: the mockup's play/pause characters rendered
    // as colour emoji on this font - orange, square in the middle of an
    // accent-filled circle. A triangle and two bars are not glyphs anyone's
    // font substitutes a different one for.
    Canvas {
        id: glyph
        anchors.centerIn: playButton
        width: playButton.width * 0.34
        height: playButton.height * 0.34

        property bool playing: root.isPlaying
        property bool awaiting: root.isAwaitingMe
        property color tint: root.ink
        onPlayingChanged: requestPaint()
        onAwaitingChanged: requestPaint()
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = tint;
            ctx.strokeStyle = tint;

            if (awaiting) {
                // A ring, not a full circle - a complete one at this size
                // reads as a filled dot, not "loading".
                ctx.lineWidth = Math.max(1.4, width * 0.16);
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, width / 2 - ctx.lineWidth / 2,
                         -Math.PI / 2, Math.PI * 1.1);
                ctx.stroke();
                return;
            }

            if (playing) {
                const barW = width * 0.3;
                ctx.fillRect(0, 0, barW, height);
                ctx.fillRect(width - barW, 0, barW, height);
                return;
            }

            // A right-pointing triangle, idle AND missing alike - missing
            // is a failed fetch, and the way out of it is the same tap
            // that starts a fresh one (toggle() clears `missing` itself).
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(width, height / 2);
            ctx.lineTo(0, height);
            ctx.closePath();
            ctx.fill();
        }
    }

    MouseArea {
        anchors.fill: playButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.tapped()
    }

    // ---- the bar ----

    Item {
        id: barArea
        anchors.verticalCenter: parent.verticalCenter
        x: playButton.width + 10 * root.uiScale
        width: parent.width - x - timeLabel.width - 8 * root.uiScale
        height: 14 * root.uiScale

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4 * root.uiScale
            radius: height / 2
            color: root.wash
        }

        Rectangle {
            id: trackFill
            anchors.verticalCenter: track.verticalCenter
            width: track.width * root.progress
            height: track.height
            radius: height / 2
            color: root.ink
        }

        Rectangle {
            id: handle
            anchors.verticalCenter: track.verticalCenter
            x: Math.min(Math.max(trackFill.width - width / 2, 0), track.width - width)
            width: 10 * root.uiScale
            height: width
            radius: width / 2
            color: root.ink
        }

        MouseArea {
            anchors.fill: parent
            onPressed: mouse => root.seekAt(mouse.x)
            onPositionChanged: mouse => { if (pressed) root.seekAt(mouse.x); }
        }
    }

    Text {
        id: timeLabel
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        text: root.timeText
        color: root.ink
        font.pixelSize: Math.round(11 * root.uiScale)
    }
}
