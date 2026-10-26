import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel/messages"

// ConversationView, fed fixed messages.
//
// Render fixture:
//   scripts/laserbar-preview.sh tests/laserbar/messages-thread.qml /tmp/thread.png
//   LASERBAR_VARIANT=light scripts/laserbar-preview.sh ... /tmp/thread-light.png
//
// This is the fixture where the variant actually matters. Everything else in
// Messages draws in the contact's hue, which the caller supplies; the bubble
// is @msgAccent@, and that is base0D - #008DF8 in dark and #DA103F in light.
// A render that looked identical in both would mean the token never reached
// the bubble.
//
// The thread pane is at 40,40, 600x700. Assertions that pass against this
// component, read off the render:
//
//   the SAME outgoing bubble, in each variant - this is the pair that proves
//   @msgAccent@ reaches it, since base0D is blue in one and crimson in the
//   other and a render identical in both would mean the token never arrived
//     dark:  probe 480 484 40 8 --near '#008df8' 20
//     light: probe 480 484 40 8 --near '#da103f' 20
//   an incoming bubble is the plate, and the same probe rejects the accent
//     probe 180 444 40 8 --near '#131312' 14
//
// Probe the PADDING of a bubble, never its middle. The middle is text, and a
// region average over glyphs is the font's opinion: the same incoming bubble
// reads #131312 across its padding and #565451 across its words.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF101010"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        MessageTokens { id: tok }
        MessageHue { id: pal }

        Rectangle {
            x: 40; y: 40
            width: 600; height: 700
            color: tok.sheetBg

            ConversationView {
                anchors.fill: parent
                uiScale: 1
                title: "Lauren Ulrich"
                initials: "LU"
                hue: pal.hues[5]
                // The pane says so while a page is in flight, because the
                // phone can take a moment and a thread that just sat there
                // looks like a thread with nothing in it.
                loadingOlder: true

                // Newest first - the order MessageStore.messages() returns
                // and the order the view expects. Feeding it oldest-first
                // renders the conversation upside down.
                messages: [
                    { id: "m5", body: "",
                      ts: new Date(2026, 9, 26, 8, 32).getTime(),
                      outgoing: true, delivered: true,
                      attachments: [{ partId: 7, name: "entrance.jpg", path: "" }] },
                    { id: "m4", body: "Perfect. Here's the entrance, it's the side door.",
                      ts: new Date(2026, 9, 26, 8, 31).getTime(),
                      outgoing: true, attachments: [] },
                    { id: "m3", body: "Thanks so much! I should be there by 9:00.",
                      ts: new Date(2026, 9, 26, 8, 25).getTime(),
                      outgoing: false, attachments: [] },
                    { id: "m2", body: "Hey!",
                      ts: new Date(2026, 9, 26, 8, 22).getTime(),
                      outgoing: false, attachments: [] },
                    { id: "m1", body: "Morning — still good for the 9am?",
                      ts: new Date(2026, 9, 26, 8, 14).getTime(),
                      outgoing: true, attachments: [] }
                ]
            }
        }
    }
}
