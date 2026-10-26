import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel/messages"

// MessageAvatar in its four states, on a flat ground.
//
// Render fixture:
//   scripts/laserbar-preview.sh tests/laserbar/messages-avatar.qml /tmp/av.png
//   scripts/laserbar-probe.sh /tmp/av.png <x> <y> <w> <h> --near '#rrggbb'
//
// Laid out on a 120px grid at uiScale 1, size 62, so every probe rectangle is
// arithmetic rather than a measurement:
//
//   resting   disc at 100,100 .. 162,162
//   unread    disc at 220,100 .. 282,162
//   open      disc at 340,100 .. 402,162
//   group     disc at 460,100 .. 522,162
//   shortcode disc at 580,100 .. 642,162
//
// The four assertions, which pass against this component:
//
//   open fill is THAT CONTACT'S hue - not @msgAccent@, which is the outgoing
//     bubble and has nothing to do with the avatar. #008df8 below is simply
//     what this fixture passes as Lauren's hue.
//     probe 358 107 26 8 --near '#008df8' 18
//   resting is the faint plate and NOT the contact's hue
//     probe 118 108 26 8 --near '#1d1d1d' 18
//   unread ring is the hue at full strength
//     probe 244 99 14 4 --dominant g 20
//   resting ring is the same hue at 34% - this one rejects '#00d7eb' at the
//     same tolerance, which is the point: it fails if resting goes full
//     strength and the two states stop being distinguishable
//     probe 124 99 14 4 --near '#103a3e' 22
//
// Do NOT probe a disc centre with --near. The initials sit there and a 30x30
// average over a glyph is the font's opinion, not the fill's: the open disc
// reads #0073ca rather than #008df8 that way, and the resting disc reads as
// cyan because two cyan letters are in the box.
//
// The ground is deliberately NOT the sheet colour: a resting avatar is the
// panel's glass over whatever is behind it, and probing it against an
// identical ground would pass for a component that drew nothing at all.
//
// There is no light-variant probe here, and that is not an omission. Almost
// everything this component draws is the contact's hue, which the caller
// supplies and the theme never sees; the only themed values in it are the
// plate, the knockout and the on-accent ink, and all three are dark in both
// variants. Rendering it light tells you nothing the dark render did not.
// The variant that matters is ConversationView's, where the bubble is
// @msgAccent@ and goes from blue to crimson.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF101010"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        MessageAvatar {
            x: 100; y: 100; size: 62; uiScale: 1
            initials: "MA"; hue: "#FF00D7EB"; label: "Maman"
        }

        MessageAvatar {
            x: 220; y: 100; size: 62; uiScale: 1
            initials: "BP"; hue: "#FF27D796"; label: "Benjamin"
            unread: true
        }

        MessageAvatar {
            x: 340; y: 100; size: 62; uiScale: 1
            initials: "LU"; hue: "#FF008DF8"; label: "Lauren"
            open: true
        }

        MessageAvatar {
            x: 460; y: 100; size: 62; uiScale: 1
            initials: "TG"; hue: "#FFF1895C"; label: "Appart 4B"
            secondInitials: "AC"; secondHue: "#FF6C43A5"
        }

        // No contact card: no initials to show, so it wears its own number.
        MessageAvatar {
            x: 580; y: 100; size: 62; uiScale: 1
            initials: ""; hue: "#FFB5B0AA"; label: "32665"
        }
    }
}
