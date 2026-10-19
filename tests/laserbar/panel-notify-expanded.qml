import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// The same, with the Signal group opened: every entry visible, each one
// its own target, divided by a beam. Not driven through
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
            expanded: ({ "Signal": true })
            groups: [
                { app: "Signal", count: 3, items: [
                    { appName: "Signal", summary: "Marie", body: "On arrive dans 10 minutes" },
                    { appName: "Signal", summary: "Marie", body: "On est en bas" },
                    { appName: "Signal", summary: "Groupe projet", body: "Reunion decalee" } ] },
                { app: "Syncthing", count: 1, items: [
                    { appName: "Syncthing", summary: "Folder up to date", body: "notes - 42 files" } ] },
                { app: "System", count: 1, items: [
                    { appName: "System", summary: "Battery at 20%", body: "About 48 minutes left" } ] }
            ]
        }
    }
}
