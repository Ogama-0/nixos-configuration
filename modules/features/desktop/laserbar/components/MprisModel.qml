import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Which player the music card and the bar capsule obey. ONE of these, in
// shell.qml, so the card, the capsule, the progress poll and every button
// address the same thing.
//
// Both used to pick "the first player on the bus that says it is playing",
// which breaks the moment kdeconnect is connected: the phone exports its
// media as a local MPRIS player, and a phone left mid-song sits at
// PlaybackStatus=Playing indefinitely. So pausing Deezer handed the widget
// to the phone without a visible change, and the next press of play - or
// next, or a drag on the progress bar - went out to the phone instead of to
// the thing just paused.
//
// The choice is therefore a memory rather than a scan: whoever most recently
// *started* playing keeps the widget until someone else starts playing. A
// pause does not give it up (that is the play/pause case), and a player that
// was already playing when we first saw it cannot take it - the phone
// appearing mid-song started nothing here.
Item {
    id: root

    // The chosen player, or null when nothing is loaded anywhere.
    readonly property var player: root.choose(Mpris.players ? Mpris.players.values : [])

    readonly property bool playing: root.player !== null && root.player.isPlaying

    // The phone, reaching us through kdeconnect's MPRIS bridge. Everything
    // about it is second hand: the metadata is a copy, the controls are
    // messages, and the audio is not here at all (see RemoteSpectrum.qml).
    readonly property bool remote: root.player !== null
        && root.player.dbusName.startsWith("org.mpris.MediaPlayer2.kdeconnect")

    // `playerctl -p` wants the bus name without the well-known prefix.
    readonly property string playerctlName: root.player
        ? root.player.dbusName.replace("org.mpris.MediaPlayer2.", "")
        : ""

    // dbusName of whoever started playing last, "" until we see a start.
    property string startedId: ""

    // The two taken as read at the last bus change. MPRIS publishes a state,
    // not a transition, so the start we care about is this diff.
    property var playingIds: []
    property var seenIds: []

    // Names and play flags, in one string: a change here is a change worth
    // re-reading, and - unlike a var holding an array - an unchanged one
    // emits nothing.
    readonly property string busKey: {
        const list = Mpris.players ? Mpris.players.values : []
        let key = ""
        for (let i = 0; i < list.length; i++) {
            key += list[i].dbusName + (list[i].isPlaying ? "=p;" : "=x;")
        }
        return key
    }

    onBusKeyChanged: root.noteBus(Mpris.players ? Mpris.players.values : [])

    // Split out of the bindings above so a fixture can drive the decision
    // with fake players, which is the only way to test it without a phone.
    function noteBus(list) {
        const nowPlaying = []
        const seen = []
        for (let i = 0; i < list.length; i++) {
            seen.push(list[i].dbusName)
            if (list[i].isPlaying) nowPlaying.push(list[i].dbusName)
        }
        for (let i = 0; i < nowPlaying.length; i++) {
            const id = nowPlaying[i]
            if (root.seenIds.indexOf(id) !== -1 && root.playingIds.indexOf(id) === -1) {
                root.startedId = id
            }
        }
        root.playingIds = nowPlaying
        root.seenIds = seen
    }

    function choose(list) {
        let playing = null
        let loaded = null
        for (let i = 0; i < list.length; i++) {
            const p = list[i]
            if (p.playbackState === MprisPlaybackState.Stopped) continue
            if (p.dbusName === root.startedId) return p
            if (!playing && p.isPlaying) playing = p
            if (!loaded) loaded = p
        }
        // Nobody remembered: nothing has started since the shell came up, or
        // it left the bus. Fall back to the old scan.
        return playing || loaded
    }
}
