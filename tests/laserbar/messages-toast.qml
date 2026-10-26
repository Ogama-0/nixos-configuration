import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel/messages"

// MessageToast, in both of its states.
//
//   scripts/laserbar-preview.sh tests/laserbar/messages-toast.qml /tmp/toast.png
//   LASERBAR_VARIANT=light scripts/laserbar-preview.sh ... /tmp/toast-light.png
//
// Two toasts so the render shows the reply row and the confirmation side by
// side. Assertions, read off the render:
//
//   the send button is @msgAccent@, at the 35% it wears with nothing typed.
//   Dimmed, not absent: a send button that only appeared once you had typed
//   would leave you looking for it. The pair is the assertion - base0D is
//   blue in one variant and crimson in the other, so a render that matched
//   in both would mean the token never reached the toast.
//     dark:  probe 384 110 10 8 --near '#012e51' 24
//     light: probe 384 110 10 8 --near '#da919f' 24
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF101010"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        MessageHue { id: pal }

        MessageToast {
            x: 40; y: 40
            uiScale: 1
            title: "Benjamin Poussart"
            initials: "BP"
            preview: "On se voit demain ? J'ai récupéré les clés."
            hue: pal.hues[1]
            convId: "29"
        }

        MessageToast {
            x: 40; y: 220
            uiScale: 1
            title: "Uber"
            initials: ""
            preview: "[Uber] Votre code : 1358. Ne le divulguez jamais."
            hue: pal.hues[3]
            convId: "30"
            sent: true
        }
    }
}
