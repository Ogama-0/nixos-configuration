import QtQuick
import Quickshell
import "components/panel"

// Two toasts, top right, pushed in directly. Not driven through the
// notification server: that needs something to actually send one.
//
// They must use the same plate and the same row as the centre - a toast
// that looks different from its own entry in the list is two designs.
Scope {
    NotificationToasts {
        id: toasts
        uiScale: 1
        Component.onCompleted: {
            toasts.show({ appName: "Signal", summary: "Marie",
                          body: "On arrive dans 10 minutes" });
            toasts.show({ appName: "Syncthing", summary: "Folder up to date",
                          body: "notes - 42 files" });
        }
    }
}
