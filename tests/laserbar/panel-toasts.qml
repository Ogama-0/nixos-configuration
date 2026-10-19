import QtQuick
import Quickshell
import "components/panel"

// Four notifications from two apps, pushed in directly: they must become
// TWO toasts, the Signal one carrying a count of 3. Not driven through the
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
            // Same app twice more: these must PACK into the Signal toast
            // with a count, not open two more toasts.
            toasts.show({ appName: "Signal", summary: "Marie",
                          body: "On est en bas" });
            toasts.show({ appName: "Signal", summary: "Groupe projet",
                          body: "Reunion decalee" });
            // Opened in place: a packed toast shows what its count hides
            // without sending you to the centre. Found by app rather than
            // by index - packing reorders nothing, so the Signal toast is
            // not the first one.
            for (const t of toasts.live)
                if (t.app === "Signal") toasts.toggle(t.born);
        }
    }
}
