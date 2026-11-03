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
//     dark:  probe 480 420 40 8 --near '#008df8' 10
//     light: probe 480 420 40 8 --near '#da103f' 20
//   an incoming bubble is the plate, and the same probe rejects the accent
//     dark:  probe 75  464 15  6 --near '#131312' 10
//     light: probe 75  464 15  6 --near '#e5d9d6' 10
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
                      // Inline bytes, which is how an image really arrives -
                      // base64EncodedFile populated on the first
                      // announcement, no path and nothing fetched. A flat
                      // magenta square so the probe can tell "the photo
                      // rendered" from "the recess rendered"; it stood in
                      // for a stale `name`/empty `path` pair that could only
                      // ever draw the placeholder.
                      attachments: [{ partId: 7, mime: "image/png",
                                      uid: "PART_entrance.png", path: "",
                                      data: "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAATElEQVR42u3PMQkAAAwDsPo33UnoPQjEQNL0tQgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgILAdBp+HSRtACMAAAAABJRU5ErkJggg==" }] },
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
