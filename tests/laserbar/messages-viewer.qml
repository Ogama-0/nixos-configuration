import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel/messages"

// PictureViewer, two instances: a picture that arrived, and one that did
// not.
//
// Render fixture:
//   scripts/laserbar-preview.sh tests/laserbar/messages-viewer.qml /tmp/pv.png
//   LASERBAR_VARIANT=light scripts/laserbar-preview.sh ... /tmp/pv-light.png
//
// Left instance at (40,40)/600x460, carrying a repo-local base64 PNG (a flat
// mid-blue square, 64x48) rather than the real kdeconnect cache path under
// ~/.cache - that path is machine-specific, and a fixture that depends on it
// only works on the one machine that happened to sync this phone.
//
// Right instance at (660,40)/600x460, `missing: true` - a picture that is
// neither inline nor fetchable (Review Focus 5). A probe against a blank
// frame asserts nothing; the one that matters here is the "did not send"
// text actually drawing something over the sheet ground, not holding it
// empty.
//
// Assertions that pass against this component, read off the render:
//
//   the foot strip is @plateBg@, lighter than the sheet ground above it -
//   proves the 44px strip at the bottom is really drawn and not text
//   floating straight on the sheet
//     dark:  probe 60  466 10 10 --near '#171716' 10
//     light: probe 60  466 10 10 --near '#eadede' 12
//   the image area in the LEFT instance is the test picture's flat fill -
//   PreserveAspectFit letterboxes this wide a frame against this image's
//   4:3, so the probe sits 40px right of the margin to clear the gap, not
//   at the corner - same colour in both variants, since the picture's own
//   bytes carry no token
//     both: probe 100 60 10 10 --near '#50a0dc' 10
//
//   the RIGHT instance (missing: true) never drew a picture - its sheet
//   corner, well clear of the centred text, reads the plain ground
//     dark:  probe 680 60 10 10 --near '#000000' 6
//     light: probe 680 60 10 10 --near '#fcf0ed' 6
//   and the "did not send" text itself is NOT a blank frame: measured
//   bounding box of its glyphs is 847,243 226x13 (`convert -fuzz 10%
//   -transparent <bg> -trim` against the sheet corner above), averaging
//   noticeably off the bare ground in both variants - this is the one
//   place in this fixture that is deliberately a glyph average rather
//   than a padding probe (same exception messages-voice.qml takes for its
//   Canvas glyph), because "the frame says so" IS the thing under test and
//   nothing else here would catch a message that silently failed to render
//     dark:  probe 847 243 226 13 --near '#252423' 10
//     light: probe 847 243 226 13 --near '#dcd1cf' 10
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
            width: 600; height: 460
            color: tok.sheetBg

            PictureViewer {
                anchors.fill: parent
                uiScale: 1
                // 64x48 flat #50A0DC PNG, generated for this fixture.
                source: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAAAwCAIAAAAuKetIAAAAZElEQVR4nO3PUQkAIBTAwBfRiAYzjCH8OITBAtxm7fN1wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY8dgHxS5E8ayJMEgAAAABJRU5ErkJggg=="
                who: "Lauren Ulrich"
                when: "Today 08:32"
            }
        }

        Rectangle {
            x: 660; y: 40
            width: 600; height: 460
            color: tok.sheetBg

            PictureViewer {
                anchors.fill: parent
                uiScale: 1
                source: ""
                who: "Lauren Ulrich"
                when: "Today 08:33"
                // missing is derived from source === "" now, not a second
                // settable property - see PictureViewer's own comment.
            }
        }
    }
}
