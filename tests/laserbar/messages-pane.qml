import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel/messages"

// The whole pane on the control panel's real 940x700 stage, so the render can
// be held next to docs/previews/messages-panel.html.
//
// MessagesPane owns its own models, and they are live: ContactsModel reads
// the real vCard directory and MessagesModel would shell out to busctl. So
// this fixture does NOT use MessagesPane - it assembles the same three views
// from fixed data, which is the only way to get a render that looks the same
// on a machine with a different phone.
//
// What MessagesPane itself adds over this - the wiring - is covered by
// messages-model.qml and messages-compose.qml.
//
//   scripts/laserbar-preview.sh tests/laserbar/messages-pane.qml /tmp/pane.png
//   LASERBAR_VARIANT=light scripts/laserbar-preview.sh ... /tmp/pane-light.png
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
            x: 40; y: 20
            width: 940; height: 700
            radius: 22
            color: tok.sheetBg
            clip: true

            readonly property var convs: [
                { convId: "1", title: "Maman", number: "+33600000001",
                  preview: "Tu rentres ce week-end ?", ts: Date.now() - 86400000,
                  unread: false, pinned: true, isGroup: false,
                  initials: "MA", hue: pal.hues[4] },
                { convId: "2", title: "Benjamin Poussart", number: "+33767248570",
                  preview: "On se voit demain ? J'ai récupéré les clés.",
                  ts: Date.now() - 600000, unread: true, pinned: true,
                  isGroup: false, initials: "BP", hue: pal.hues[1] },
                { convId: "3", title: "Lauren Ulrich", number: "+33600000003",
                  preview: "Thanks so much! I should be there by 9:00.",
                  ts: Date.now() - 3600000, unread: false, pinned: true,
                  isGroup: false, initials: "LU", hue: pal.hues[5] },
                { convId: "4", title: "Appart 4B", number: "+33600000004",
                  preview: "Thomas : je passe l'aspirateur ce soir",
                  ts: Date.now() - 90000000, unread: false, pinned: true,
                  isGroup: true, initials: "TG", hue: pal.hues[6],
                  secondInitials: "AC", secondHue: pal.hues[7] },
                { convId: "5", title: "Justin Shumaker", number: "+33600000005",
                  preview: "I'd love to hear more about your project.",
                  ts: Date.now() - 172800000, unread: false, pinned: true,
                  isGroup: false, initials: "JS", hue: pal.hues[2] },
                { convId: "6", title: "Zoé", number: "+33600000006",
                  preview: "ok !", ts: Date.now() - 259200000,
                  unread: false, pinned: true, isGroup: false,
                  initials: "ZK", hue: pal.hues[7] },
                { convId: "7", title: "Uber", number: "Uber",
                  preview: "[Uber] Votre code : 1358. Ne le divulguez jamais.",
                  ts: Date.now() - 400000000, unread: false, pinned: false,
                  isGroup: false, initials: "", hue: pal.hues[3] }
            ]

            ThreadList {
                id: list
                x: 0; y: 0
                width: 340; height: parent.height
                uiScale: 1
                activeId: "3"
                conversations: parent.convs
            }

            Rectangle {
                x: list.width; width: 1; height: parent.height
                color: tok.glassBorder
            }

            ConversationView {
                x: list.width + 1; y: 0
                width: parent.width - x
                height: parent.height - 56
                uiScale: 1
                title: "Lauren Ulrich"
                initials: "LU"
                hue: pal.hues[5]
                loadingOlder: true
                messages: [
                    { id: "m5", body: "", ts: new Date(2026, 9, 26, 8, 32).getTime(),
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

            ComposeRow {
                x: list.width + 1
                y: parent.height - height
                width: parent.width - x
                uiScale: 1
                enabled: true
            }
        }
    }
}
