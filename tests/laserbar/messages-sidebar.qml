import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel/messages"

// ThreadList, fed fixed data.
//
// No model. The sidebar's job is to lay out conversations it was handed, and
// a fixture that drove it through MessagesModel would be asserting on what
// the phone happened to have said that morning.
//
// Render fixture:
//   scripts/laserbar-preview.sh tests/laserbar/messages-sidebar.qml /tmp/side.png
//
// The sidebar is at 40,40, 340 wide, 700 tall - the real width from the
// design. Assertions that pass against this component:
//
//   the unread row's 2px rail is that contact's hue (orange, Benjamin)
//     probe 40 300 2 34 --near '#f1895c' 20
//   the selected row carries a raised plate...
//     probe 300 350 60 8 --near '#5c5a58' 22
//   ...and an unselected row at the same x is bare sheet. The pair is the
//   assertion: either one alone passes against a list that plates every row
//   or none of them.
//     probe 300 420 60 8 --near '#000000' 18
//   the pinned grid's open avatar is filled with its hue (blue, Lauren)
//     probe 300 108 20 6 --near '#008df8' 20
//
// Those coordinates come from the render, not from arithmetic: the rows sit
// under a grid whose height depends on how the names wrap, so deriving them
// from the component's internals would make every spacing change a failure.
// Re-read them off the png when the layout moves.
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
            width: 340; height: 700
            // Through MessageTokens, not spelled out. A fixture gets no
            // @token@ substitution of its own, and hardcoding the dark sheet
            // here made the light render draw light text on a black ground -
            // the component was fine and the fixture was lying.
            color: tok.sheetBg

            ThreadList {
                anchors.fill: parent
                uiScale: 1
                activeId: "c-lauren"

                conversations: [
                    { convId: "c-maman", title: "Maman", number: "+33600000001",
                      preview: "Tu rentres ce week-end ?", ts: Date.now() - 86400000,
                      unread: false, pinned: true, isGroup: false,
                      initials: "MA", hue: pal.hues[4] },
                    { convId: "c-benjamin", title: "Benjamin Poussart", number: "+33767248570",
                      preview: "On se voit demain ? J'ai récupéré les clés.",
                      ts: Date.now() - 600000,
                      unread: true, pinned: true, isGroup: false,
                      initials: "BP", hue: pal.hues[1] },
                    { convId: "c-lauren", title: "Lauren Ulrich", number: "+33600000003",
                      preview: "Thanks so much! I should be there by 9:00.",
                      ts: Date.now() - 3600000,
                      unread: false, pinned: true, isGroup: false,
                      initials: "LU", hue: pal.hues[5] },
                    { convId: "c-appart", title: "Appart 4B", number: "+33600000004",
                      preview: "Thomas : je passe l'aspirateur ce soir",
                      ts: Date.now() - 90000000,
                      unread: false, pinned: true, isGroup: true,
                      initials: "TG", hue: pal.hues[6],
                      secondInitials: "AC", secondHue: pal.hues[7] },
                    { convId: "c-justin", title: "Justin Shumaker", number: "+33600000005",
                      preview: "I'd love to hear more about your project.",
                      ts: Date.now() - 172800000,
                      unread: false, pinned: true, isGroup: false,
                      initials: "JS", hue: pal.hues[2] },
                    { convId: "c-zoe", title: "Zoé", number: "+33600000006",
                      preview: "ok !", ts: Date.now() - 259200000,
                      unread: false, pinned: true, isGroup: false,
                      initials: "ZK", hue: pal.hues[7] },
                    // Unpinned, below the grid.
                    { convId: "c-paul", title: "Paul Mercier", number: "+33600000007",
                      preview: "Je t'envoie le doc ce soir.", ts: Date.now() - 300000000,
                      unread: false, pinned: false, isGroup: false,
                      initials: "PM", hue: pal.hues[3] },
                    // No contact card: the number stands in for the name, and
                    // the avatar has no initials to draw.
                    { convId: "c-32665", title: "32665", number: "32665",
                      preview: "Votre code de confirmation est 418293.",
                      ts: Date.now() - 400000000,
                      unread: false, pinned: false, isGroup: false,
                      initials: "", hue: tok.muted }
                ]
            }
        }
    }
}
