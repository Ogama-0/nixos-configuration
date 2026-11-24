import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// The desktop music CARD - Music.qml, not the bar's MusicWidget. Every other
// music-*.qml fixture here drives the little capsule on the bar; this one is
// the 440x400 card on the wallpaper, and it exists because the card carries
// the two Shapes that replaced the shell's Canvases.
//
// What to look at:
//
//   * The nine concentric rings behind the cover. They must be nine distinct
//     wobbling outlines, brightest through the middle of the stack and
//     fading at the inner and outer edges, with the palette swept ACROSS
//     them - not nine rings in one flat colour. A flat ring stack means the
//     fillGradient stopped applying; nothing at all means rule 4 bit (see
//     docs/adding-a-bar-widget.md) and a ShapePath is being fed data it did
//     not have at load.
//   * The progress bar's strands: three or four coloured sine lines up to
//     the playhead, then a flat divider line to the right edge.
//
// `remote: true` is what makes the card visible without a Deezer window -
// the same path a phone track over KDE Connect takes. The levels are a
// literal so the wave is the fixture's, not this machine's audio.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF101018"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
    }

    // Stands in for an MprisPlayer. Music.qml only ever reads these.
    QtObject {
        id: stubPlayer
        property bool isPlaying: true
        property string trackTitle: "Weightless Again"
        property string trackArtist: "The Handsome Family"
        property string trackAlbum: "Through the Trees"
        property real length: 240
        property real position: 72
        property bool canSeek: true
        property bool canGoNext: true
        property bool canGoPrevious: true
        property bool canTogglePlaying: true
        function next() {}
        function previous() {}
        function togglePlaying() {}
    }

    Music {
        id: card
        activePlayer: stubPlayer
        // A name nothing answers to, on purpose. The nested compositor shares
        // the real session bus, so a blank name let `playerctl -p "" position`
        // answer with whatever is actually playing on this machine - the first
        // run of this fixture rendered a 25:27 playhead against a 4:00 track
        // and drew the strands across the full width. With no match the parse
        // fails, nothing overwrites the playhead set at the bottom of this
        // file, and the render is the fixture's own.
        playerctlName: "no-such-player-fixture"
        remote: true
        // Twenty bands, the count cava is configured for, with enough spread
        // that the rings visibly deform instead of sitting as circles.
        remoteLevels: [12, 48, 90, 64, 30, 76, 95, 52, 18, 66,
                       22, 58, 84, 40, 70, 28, 88, 44, 60, 34]
        // A four-colour palette, the longest case, so the gradient sweep has
        // every stop populated. Drawn from the Jinx artwork the dark
        // lockscreen uses.
        coverPalette: ["#FF2E86", "#33E6D8", "#FFB23D", "#F3F0EA"]
    }

    // The playhead, set after load rather than as a binding on the Music
    // block above: `onTrackKeyChanged` fires once as the stub's track lands
    // and resets livePosition to 0, which would silently undo an initial
    // value and leave the progress strands with nothing to draw.
    Timer {
        interval: 250
        running: true
        repeat: false
        onTriggered: card.livePosition = 110
    }
}
