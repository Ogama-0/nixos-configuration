import QtQuick
import QtMultimedia
import Quickshell.Io

// The one audio player for the whole Messages panel - every voice-note
// bubble asks THIS to play, rather than owning a MediaPlayer each. Two
// screens would otherwise mean two decoders and two sound-card handles
// fighting over the same note, the same problem MessagesCore already solved
// for the SQLite connection and the vCard read.
//
// `player` is injected for the same reason `contacts`/`palette`/`store` are
// injected on MessagesModel: a fixture drives the state machine - one
// playing id, one outstanding fetch, a seek clamp, a timeout - without a
// sound card or an ffmpeg plugin anywhere nearby. The real MediaPlayer is
// trusted; nothing in CI will ever play a sound (spec, Testing). Its only
// job here is the default value of `player`, swapped out in
// tests/laserbar/messages-audio.qml for a QtObject that counts calls and
// lets position/duration be poked directly, standing in for what the real
// player does when seeked or finishing a load.
Item {
    id: root

    // Which bubble, if any, owns the player right now. "" means nothing is
    // playing AND nothing is paused - the two are not distinguished further,
    // because a bubble only ever needs to know "is it me".
    property string playingId: ""
    property bool paused: false

    // Updated from the player on a timer of OUR choosing (see `ticker`
    // below), not bound straight to it. A real MediaPlayer fires
    // positionChanged roughly every 40ms; binding a delegate to that
    // directly would make the bar's repaint rate a property of the decoder
    // rather than a decision Task 3 gets to make.
    property real position: 0
    property real duration: 0

    property var player: internalPlayer
    property var store: null

    // How long a requested attachment gets before the bubble gives up and
    // says so, rather than sitting in "fetching..." forever if kdeconnectd
    // never answers (phone asleep, SMS plugin wedged, bus message dropped).
    property int fetchTimeoutMs: 15000

    // Set when a fetch's timeout fires with nothing arriving. Cleared by the
    // next toggle() on any note, and by a successful fileArrived().
    property bool missing: false

    // The uid we are waiting on a file for, "" when nothing is outstanding.
    // Doubles as the guard in fileArrived(): an attachment landing for a uid
    // that is not this one is some OTHER bubble's fetch finishing after the
    // thread moved on, and must be ignored rather than started.
    property string pendingUid: ""
    property string pendingMsgId: ""

    readonly property bool awaiting: root.pendingUid !== ""

    // The real attachment part id (MessagesModel.parseMessage's a[0]), NOT
    // derived from anything here - it is unrelated to the message id and a
    // wrong value asks kdeconnectd for the wrong part, or one that does not
    // exist. toggle() carries it through from whoever holds the attachment
    // struct (the voice bubble, which has {partId, mime, data, uid, path}).
    signal fetchAsked(int partId, string uid)

    MediaPlayer {
        id: internalPlayer
        audioOutput: AudioOutput {}
    }

    // Nothing else here ever hears a note reach the end of its own file -
    // every other transition (switching notes, stop(), a vanished path) is
    // something THIS component decided and already cleans up after. A note
    // that simply finishes does not: the player settles into StoppedState
    // on its own, and without this, playingId stays set forever - the
    // ticker keeps polling a stopped player, the glyph stays on the pause
    // bars, isActive stays true so the time freezes at the final position,
    // and the next tap on that bubble calls toggle() down the "same id"
    // branch, which pauses an already-stopped player instead of restarting
    // it - the first tap after a note ends is always wasted.
    // `root.player` is a `var`, swapped for the test stub, so this targets
    // it through a `Connections` rather than a static `onPlaybackStateChanged`
    // on `internalPlayer` directly - the stub needs to drive the same path.
    Connections {
        target: root.player
        function onPlaybackStateChanged(): void {
            if (root.player.playbackState === 0 && root.playingId !== "")
                root.stop();
        }
    }

    // A pure existence probe, not a reader - `blockLoading` is what makes
    // `text()` below a synchronous stat rather than kicking off an async
    // load the caller would need a signal to find out about. Nothing reads
    // the content back; `onLoaded`/`onLoadFailed` only flip `_probeOk`,
    // which `playable()` reads the instant `text()` returns.
    FileView {
        id: existsProbe
        blockLoading: true
        printErrors: false
        watchChanges: false
        onLoaded: root._probeOk = true
        onLoadFailed: error => root._probeOk = false
    }

    property bool _probeOk: false

    // Polls the player rather than reacting to every positionChanged, so the
    // update rate is this component's to decide (see `position` above).
    Timer {
        id: ticker
        interval: 250
        repeat: true
        running: root.playingId !== "" && !root.paused
        onTriggered: {
            root.position = root.player.position;
            root.duration = root.player.duration;
        }
    }

    Timer {
        id: fetchTimer
        interval: root.fetchTimeoutMs
        repeat: false
        onTriggered: {
            root.missing = true;
            root.pendingUid = "";
            root.pendingMsgId = "";
        }
    }

    // m:ss - no leading zero on the minute, because nothing here runs past
    // an hour (a voice note that long is not a thing KDE Connect carries).
    function clock(ms: real): string {
        const totalSeconds = Math.max(0, Math.floor(ms / 1000));
        const m = Math.floor(totalSeconds / 60);
        const s = totalSeconds % 60;
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    // encodeURI does not treat "%" as safe, so it escapes the literal "%"
    // in e.g. "Audio%20Mes1.amr" into "%2520" on its own. That double-escape
    // is exactly right: the "%20" on disk is not an encoded space, it is
    // three literal characters, and the one decode a media backend performs
    // on a file:// URL has to land back on "%20Mes1.amr", not " Mes1.amr".
    function fileUrl(path: string): string {
        return "file://" + encodeURI(path);
    }

    // A fraction, not a pixel width - the bar decides its own geometry.
    // Guards duration<=0 explicitly rather than trusting division to do it:
    // 0/0 is NaN, and a NaN width on a Rectangle does not clip, it paints
    // the full bar, which looks exactly like 100% progress on a note that
    // has not even told us how long it is yet.
    function progressAt(position: real, duration: real): real {
        if (duration <= 0) return 0;
        return position / duration;
    }

    // An existence check, not a content read - whether the row's cached
    // path still points at a real file, e.g. because kdeconnectd's own
    // cache GC or an unpaired-and-repaired phone took it out from under a
    // conversation that still has the old path recorded.
    function playable(path: string): bool {
        if (!path) return false;
        root._probeOk = false;
        // FileView's `path` setter is a no-op when the new value equals the
        // old one - fine for a file that is only ever read once, wrong
        // here: the same voice note can be checked twice (once by a bubble
        // deciding whether to play it, once inside toggle()'s own gate),
        // and the second check must re-stat rather than replay whatever
        // `_probeOk` the first one left behind. Routing through "" first
        // forces a real transition both times.
        existsProbe.path = "";
        existsProbe.path = path;
        existsProbe.text();
        return root._probeOk;
    }

    function seekTo(ms: real): void {
        const max = root.player.duration || 0;
        const clamped = Math.max(0, Math.min(ms, max));
        root.player.position = clamped;
        root.position = clamped;
    }

    function skip(deltaMs: real): void {
        root.seekTo(root.player.position + deltaMs);
    }

    function stop(): void {
        root.player.stop();
        root.playingId = "";
        root.paused = false;
        root.position = 0;
        root.duration = 0;
        root.pendingUid = "";
        root.pendingMsgId = "";
        root.missing = false;
        fetchTimer.stop();
    }

    // Three ways in: the bubble that is already playing (pause/resume in
    // place), a bubble with a file ready to go, and a bubble whose
    // attachment has never been fetched. `partId` is only used on the third
    // path (raising fetchAsked); callers that already have a path can pass
    // anything there (0, say), since it is never read in that branch.
    function toggle(msgId: string, path: string, uid: string, partId: int): void {
        if (msgId === root.playingId && root.playingId !== "") {
            if (root.paused) { root.player.play(); root.paused = false; }
            else { root.player.pause(); root.paused = true; }
            return;
        }

        // Wanting something else invalidates whatever was sounding AND
        // whatever fetch we were sitting on - an old bubble's file landing
        // after the thread moved on must not suddenly start playing.
        if (root.playingId !== "") root.player.stop();
        root.playingId = "";
        root.paused = false;
        root.position = 0;
        root.duration = 0;
        root.pendingUid = "";
        root.pendingMsgId = "";
        root.missing = false;
        fetchTimer.stop();

        if (!path) {
            root.pendingUid = uid;
            root.pendingMsgId = msgId;
            fetchTimer.restart();
            root.fetchAsked(partId, uid);
            return;
        }

        // The row can hold a path left over from a fetch that already
        // succeeded once - and the file that answer pointed at can be gone
        // by the time the bubble is tapped again. Handing a dangling
        // file:// URL to QtMultimedia is not the failure mode to court;
        // "missing" is the honest answer, and re-asking kdeconnectd would
        // be lying about why (the row never said it lacked a path).
        if (!root.playable(path)) {
            root.missing = true;
            return;
        }

        root.startPlaying(msgId, path);
    }

    // The real MediaPlayer needs `source` set before play().
    function startPlaying(msgId: string, path: string): void {
        root.playingId = msgId;
        root.player.source = root.fileUrl(path);
        root.player.play();
    }

    // The file a fetchAsked() eventually answers. Plays it only if it is
    // still the one we are waiting on - see the comment on pendingUid.
    function fileArrived(uid: string, path: string): void {
        if (root.pendingUid === "" || uid !== root.pendingUid) return;
        const msgId = root.pendingMsgId;
        root.pendingUid = "";
        root.pendingMsgId = "";
        root.missing = false;
        root.position = 0;
        root.duration = 0;
        fetchTimer.stop();
        root.startPlaying(msgId, path);
    }
}
