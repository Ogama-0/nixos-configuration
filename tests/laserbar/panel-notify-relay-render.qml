import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// A relay grouped by the PHONE's app, not by the courier. Three Deezer\n// notifications pack into one group headed 'Deezer'; Finamp is its own;\n// Thunderbird is a normal app and unaffected. Relayed rows print only\n// their body, because their summary IS the group's header. Not driven through
// NotificationServer: that one owns a bus, and a render fixture must not
// depend on what this desktop happens to be shouting about.
//
// Pane at 100,100, 262x400, uiScale 1. Rows are 50 tall with 8 gaps,
// starting at y 128:
//   row 0  y 128..178      row 1  y 186..236      row 2  y 244..294
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        NotificationPane {
            x: 100
            y: 100
            width: 262
            height: 400
            uiScale: 1
            expanded: ({ "relay-deezer": true })
            groups: [
                { key: "relay-deezer", app: "Deezer", relay: true, count: 3, items: [
                    { uid: "d1", appName: "KDE Connect", summary: "Deezer", body: "Detestable: Dali" },
                    { uid: "d2", appName: "KDE Connect", summary: "Deezer", body: "Ne me quitte pas" },
                    { uid: "d3", appName: "KDE Connect", summary: "Deezer", body: "La Boheme" } ] },
                { key: "relay-finamp", app: "Finamp", relay: true, count: 1, items: [
                    { uid: "f1", appName: "KDE Connect", summary: "Finamp", body: "Chapter 02 - The Vanishing Glass" } ] },
                { key: "Thunderbird", app: "Thunderbird", count: 1, items: [
                    { uid: "t1", appName: "Thunderbird", summary: "oscar.cornut@epita.fr", body: "[EPITA] 2627_I_INF_FISE_S05_A" } ] }
            ]
        }
    }
}
