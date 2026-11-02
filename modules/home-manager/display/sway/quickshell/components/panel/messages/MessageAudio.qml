import QtQuick
import QtMultimedia

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
        fetchTimer.stop();
        root.startPlaying(msgId, path);
    }
}
