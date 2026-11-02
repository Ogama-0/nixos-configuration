import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel/messages"

// VoiceBubble, four states in a column: incoming idle, outgoing idle,
// playing at ~34%, and fetching.
//
// Render fixture:
//   scripts/laserbar-preview.sh tests/laserbar/messages-voice.qml /tmp/v.png
//   LASERBAR_VARIANT=light scripts/laserbar-preview.sh ... /tmp/v-light.png
//
// Each bubble gets its OWN MessageAudio - the real pane shares one, but
// this fixture is proving what ONE bubble draws for a given state, not
// that two bubbles contend for a single player (MessageAudio's own fixture,
// tests/laserbar/messages-audio.qml, owns that question). Driving the
// "playing" and "fetching" states by poking properties directly rather than
// calling toggle() with a real path sidesteps toggle()'s playable() gate,
// which would otherwise need an actual decodable file on disk to reach
// either state at all.
//
// Four rows of 256x64 at (56,56)/(56,138)/(56,220)/(56,302), each an 8px
// margin short of the actual VoiceBubble inside it. Assertions that pass
// against this component, read off the render:
//
//   incoming's plate, not the accent - rejects a bubble drawn in the wrong
//   direction's colour
//     dark:  probe 100 60  --near '#131312' 10
//     light: probe 100 60  --near '#e5d9d6' 10
//   outgoing's accent, same check the other way - and the pair proves
//   @msgAccent@ reaches VoiceBubble the same way it reaches the text
//   bubble, since base0D is blue in one variant and crimson in the other
//     dark:  probe 100 142 --near '#008df8' 10
//     light: probe 100 142 --near '#da103f' 10
//   the played portion of row 3's bar is @msgAccentInk@ - near-black by
//   design in BOTH variants (see ConversationView's `accentInk` comment),
//   which only reads as "filled" because the unplayed portion beside it is
//   a lighter wash of the SAME ink, not because it is some other hue
//     dark:  probe 140 252 --near '#000000' 14
//            probe 220 252 --near '#006ec2' 16
//     light: probe 140 252 --near '#201c1d' 14
//            probe 220 252 --near '#b11237' 16
//
// Probe the PADDING of the fill, never a glyph - same rule as
// messages-thread.qml. These are all drawn shapes (circle wash, bar, handle,
// canvas glyph), so there is no font opinion anywhere in this fixture to
// avoid, but the handle sits ON TOP of the fill near its leading edge, so
// 140 is well behind it rather than astride it.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF101010"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        MessageTokens { id: tok }

        Rectangle {
            x: 40; y: 40
            width: 320; height: 320
            color: tok.sheetBg

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 18

                // Each row stands in for the REST of the bubble - the
                // Rectangle ConversationView actually draws the control row
                // on top of (@msgAccent@ outgoing, @plateBg@ incoming).
                // @msgAccentInk@ is near-black BY DESIGN (see
                // ConversationView's `accentInk` comment) - it only reads
                // against that fill, not against the bare sheet behind it.

                // --- incoming, idle: never played, no duration known -------
                Rectangle {
                    width: 256; height: 64
                    radius: 14
                    color: tok.plateBg
                    VoiceBubble {
                        anchors.fill: parent
                        anchors.margins: 8
                        outgoing: false
                        audio: idleAudio
                        msgId: "incoming-idle"
                        attachment: ({ partId: 1, mime: "audio/amr", data: "",
                                       uid: "PART_in.amr", path: "/does/not/matter" })
                        label: "Voice message"
                    }
                }

                // --- outgoing, idle: same state, the other fill colour -----
                Rectangle {
                    width: 256; height: 64
                    radius: 14
                    color: tok.accent
                    VoiceBubble {
                        anchors.fill: parent
                        anchors.margins: 8
                        outgoing: true
                        audio: idleAudio
                        msgId: "outgoing-idle"
                        attachment: ({ partId: 2, mime: "audio/amr", data: "",
                                       uid: "PART_out.amr", path: "/does/not/matter" })
                        label: "Voice message"
                    }
                }

                // --- playing, ~34% in -----------------------------------------
                Rectangle {
                    id: playingRow
                    width: 256; height: 64
                    radius: 14
                    color: tok.accent
                    VoiceBubble {
                        anchors.fill: parent
                        anchors.margins: 8
                        outgoing: true
                        audio: playingAudio
                        msgId: "playing"
                        attachment: ({ partId: 3, mime: "audio/amr", data: "",
                                       uid: "PART_playing.amr", path: "/does/not/matter" })
                        label: "Voice message"
                    }
                }

                // --- fetching: no file yet, asked for, nothing back yet ----
                Rectangle {
                    width: 256; height: 64
                    radius: 14
                    color: tok.plateBg
                    VoiceBubble {
                        anchors.fill: parent
                        anchors.margins: 8
                        outgoing: false
                        audio: fetchingAudio
                        msgId: "fetching"
                        attachment: ({ partId: 4, mime: "audio/amr", data: "",
                                       uid: "PART_fetching.amr", path: "" })
                        label: "Voice message"
                    }
                }
            }
        }

        MessageAudio { id: idleAudio }

        MessageAudio {
            id: playingAudio
            // A real MediaPlayer, untouched, reports position/duration 0 -
            // nothing was ever loaded into it. MessageAudio's own ticker
            // polls `player` every 250ms and would overwrite whatever this
            // fixture pokes into `position`/`duration` right back to that
            // 0 the instant it next fires. The stub stands in exactly as
            // messages-audio.qml's logic fixture does, so the poll has
            // something real to read.
            player: QtObject {
                property real position: 14280 // 34% of 42000
                property real duration: 42000
            }
            Component.onCompleted: playingAudio.playingId = "playing"
        }

        MessageAudio {
            id: fetchingAudio
            // toggle()'s no-path branch sets pendingMsgId/pendingUid and
            // raises fetchAsked - exactly what a bubble with path:"" does
            // when tapped, without actually tapping one.
            Component.onCompleted: fetchingAudio.toggle("fetching", "", "PART_fetching.amr", 4)
        }
    }
}
