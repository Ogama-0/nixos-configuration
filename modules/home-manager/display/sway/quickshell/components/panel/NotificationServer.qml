import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Quickshell owns org.freedesktop.Notifications. mako is gone: two daemons
// cannot share that bus name.
//
// This collects and NOTHING pops. Toasts are deliberately out of scope for
// now, and the consequence is known and accepted - until they exist, a
// notification is only visible by opening the panel. A half-built popup
// surface would be worse than none.
//
// The one thing in the panel that is NOT gated on being open: a notification
// centre that only listened while you were looking at it would be a list of
// things you already saw. That is why the server is a separate component
// from the pane.
//
// The list survives a quickshell restart. `keepOnReload` only covers a config
// reload - a `systemctl --user restart` is a new process and the bus has
// already closed every notification it was holding - so the list is mirrored
// to disk and read back at startup. Restored entries are display-only: the
// sender is long gone, so there is nothing left to invoke an action on, and
// dismissing one only drops it from the list. It does NOT survive a reboot
// by design; a week-old notification is clutter, not information.
Item {
    id: root

    property bool dnd: false

    readonly property int maxRetained: 50

    readonly property string statePath:
        Quickshell.env("HOME") + "/.local/state/quickshell/panel-notifications.json"

    // Read back from disk at startup; display-only.
    property var restored: []

    function recordFor(n) {
        return {
            key: (n.appName || "") + "|" + (n.summary || "") + "|" + (n.body || ""),
            appName: n.appName || "",
            summary: n.summary || "",
            body: n.body || "",
            live: true,
            ref: n
        };
    }

    // Live first, then whatever was on disk, with twins collapsed - an app
    // that re-sends the same thing after a restart should not appear twice.
    readonly property var notifications: {
        const model = server.trackedNotifications;
        const all = model ? model.values : [];
        const out = [];
        const seen = {};
        for (let i = all.length - 1; i >= 0; i--) {
            if (!all[i]) continue;
            const r = recordFor(all[i]);
            if (seen[r.key]) continue;
            seen[r.key] = true;
            out.push(r);
        }
        for (const r of restored) {
            if (seen[r.key]) continue;
            seen[r.key] = true;
            out.push(r);
        }
        return out.slice(0, maxRetained);
    }

    readonly property int count: notifications.length

    // Which entries to retire when the ceiling is passed, oldest first.
    //
    // Returned as a copy rather than dismissed in place: `list` is the live
    // model, dismissing REMOVES an entry from it, and walking it by index
    // while it shrinks under you skips every other one. Under a flood -
    // which is the only time this runs - that leaves the list permanently
    // over the ceiling.
    function overflow(list, max) {
        const excess = list.length - max;
        if (excess <= 0) return [];
        return list.slice(0, excess);
    }

    function dismiss(record) {
        if (!record) return;
        if (record.live && record.ref) {
            record.ref.dismiss();
        } else {
            restored = restored.filter(r => r.key !== record.key);
        }
        save();
    }

    function clearAll() {
        // Copied first: dismissing mutates the model being walked.
        const live = notifications.filter(r => r.live && r.ref).map(r => r.ref);
        for (const n of live) n.dismiss();
        restored = [];
        save();
    }

    function save() {
        const flat = notifications.map(r => ({
            appName: r.appName, summary: r.summary, body: r.body
        }));
        store.setText(JSON.stringify(flat));
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: notification => {
            // Without this the notification is closed the moment this
            // handler returns and the centre never sees it.
            notification.tracked = true;

            // Enforce the ceiling by retiring the oldest, not by refusing
            // the newest: the new one is the one you care about.
            const model = server.trackedNotifications;
            const all = model ? model.values : [];
            for (const old of root.overflow(all, root.maxRetained))
                if (old) old.dismiss();

            root.save();
        }
    }

    // The state directory is not created by anything else, and FileView will
    // not make it.
    Process {
        running: true
        command: ["mkdir", "-p",
                  Quickshell.env("HOME") + "/.local/state/quickshell"]
        onExited: store.reload()
    }

    FileView {
        id: store
        path: root.statePath
        atomicWrites: true
        // Our own writes would otherwise bounce straight back as a change.
        watchChanges: false

        onLoaded: {
            try {
                const saved = JSON.parse(text());
                const out = [];
                for (const e of saved) {
                    out.push({
                        key: (e.appName || "") + "|" + (e.summary || "")
                             + "|" + (e.body || ""),
                        appName: e.appName || "",
                        summary: e.summary || "",
                        body: e.body || "",
                        live: false,
                        ref: null
                    });
                }
                root.restored = out;
            } catch (err) {
                root.restored = [];
            }
        }
        // No file yet is the normal case on a fresh machine.
        onLoadFailed: root.restored = []
    }
}
