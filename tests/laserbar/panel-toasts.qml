import QtQuick
import Quickshell
import "common"
import "notification"

// Four notifications from two apps, pushed in directly: they must become
// TWO toasts, the Signal one carrying a count of 3. Not driven through the
// notification server: that needs something to actually send one.
//
// What this is for now is the header - icon, app, count, relative time, all
// in one row - and the wire down the edge. The count used to be pinned to
// the plate's corner, which is exactly where the timestamp now lives; if
// they collide again it shows up here first.
Scope {
    NowClock { id: clock; active: true }

    NotificationToasts {
        id: toasts
        uiScale: 1
        clock: clock
        Component.onCompleted: {
            const now = Date.now();
            toasts.show({ appName: "Signal", summary: "Marie",
                          body: "On arrive dans 10 minutes",
                          appIcon: "", image: "", ts: now - 5 * 60000 });
            toasts.show({ appName: "Syncthing", summary: "Folder up to date",
                          body: "notes - 42 files",
                          appIcon: "", image: "", ts: now - 90 * 60000 });
            // Same app twice more: these must PACK into the Signal toast
            // with a count, not open two more toasts.
            toasts.show({ appName: "Signal", summary: "Marie",
                          body: "On est en bas",
                          appIcon: "", image: "", ts: now - 60000 });
            toasts.show({ appName: "Signal", summary: "Groupe projet",
                          body: "Reunion decalee",
                          appIcon: "", image: "", ts: now });
            // Opened in place: a packed toast shows what its count hides
            // without sending you to the centre. Found by app rather than
            // by index - packing reorders nothing, so the Signal toast is
            // not the first one.
            for (const t of toasts.live)
                if (t.app === "Signal") toasts.toggle(t.id);
        }
    }
}
