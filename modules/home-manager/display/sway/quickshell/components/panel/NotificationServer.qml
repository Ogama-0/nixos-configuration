import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Quickshell owns org.freedesktop.Notifications. mako is gone: two daemons
// cannot share that bus name.
//
// It collects, and it raises `posted` for anything that has just arrived so
// NotificationToasts can show it. Do-not-disturb stops the toast and not the
// collecting: the point of suppressing a notification is that it does not
// interrupt you, not that you never find out.
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

    // Raised for a notification that has just arrived, so the toasts can
    // show it. Deliberately not "the newest entry in the list changed":
    // entries restored from disk at startup are new to the list and are
    // not new to you.
    signal posted(var record)

    readonly property int maxRetained: 50

    readonly property string statePath:
        Quickshell.env("HOME") + "/.local/state/quickshell/panel-notifications.json"

    // Read back from disk at startup; display-only.
    property var restored: []

    function recordFor(n) {
        return {
            // `key` is the TEXT, used to fold a restored twin into its live
            // original. `uid` is this notification and no other - two
            // messages with identical text are still two messages, and
            // selecting or deleting one must not touch the other.
            key: (n.appName || "") + "|" + (n.summary || "") + "|" + (n.body || ""),
            uid: "l" + n.id,
            appName: n.appName || "",
            summary: n.summary || "",
            body: n.body || "",
            appIcon: n.appIcon || "",
            image: n.image || "",
            // An OSD (the volume keys, the mic toggle) is not tracked, so
            // there is no live notification left to act on or dismiss - the
            // record is a copy the toast renders and then forgets.
            live: !n.transient,
            transient: n.transient === true,
            ref: n
        };
    }

    function byUid(uid) {
        for (const r of notifications) if (r.uid === uid) return r;
        return null;
    }

    // Live first, newest first, then whatever was on disk.
    //
    // Twins are collapsed only ACROSS that boundary - a restored entry that
    // matches something live is the same notification seen twice, once from
    // the bus and once from the file. Two live ones with identical text are
    // two things that happened: "Wi-Fi on" twice is the radio going down and
    // coming back, and folding them into one entry loses the second event
    // and the count on its group.
    readonly property var notifications: {
        const model = server.trackedNotifications;
        const all = model ? model.values : [];
        const out = [];
        const liveText = {};
        for (let i = all.length - 1; i >= 0; i--) {
            if (!all[i]) continue;
            const r = recordFor(all[i]);
            liveText[r.key] = true;
            out.push(r);
        }
        const seenRestored = {};
        for (const r of restored) {
            if (liveText[r.key] || seenRestored[r.key]) continue;
            seenRestored[r.key] = true;
            out.push(r);
        }
        return out.slice(0, maxRetained);
    }

    readonly property int count: notifications.length

    // Relays: apps that forward other apps' notifications under their own
    // name. Everything your phone shows arrives as "KDE Connect", so
    // packing by sender puts a message, a battery warning and a BeReal in
    // one stack - they are not one thing that happened, they only share a
    // courier.
    //
    // But they are not unrelated either. A relay puts the REAL sender in
    // the summary, so three from Deezer pack together and Finamp stays
    // its own group. Grouping by the courier is wrong; refusing to group
    // at all is only less wrong.
    property var relayApps: ["KDE Connect"]

    // Grouped by the app that sent them, newest group first, and each
    // group's items newest first. Five notifications from one chat app is
    // one thing that happened, not five - and a flood from one sender
    // should not push everything else off the list.
    readonly property var groups: {
        const order = [];
        const byKey = {};
        for (const n of notifications) {
            const app = n.appName || "Unknown app";
            const relay = relayApps.indexOf(app) >= 0;
            // Through a relay the summary IS the sender, so that is what
            // packs and what gets printed. The courier's name is dropped:
            // "KDE Connect / Deezer / Detestable" says the same thing
            // twice and buries the part you read.
            const sender = relay ? (n.summary || app) : app;
            const key = relay ? app + "\u0000" + sender : app;
            if (!byKey[key])
                { byKey[key] = { app: sender, relay: relay, items: [] };
                  order.push(key); }
            byKey[key].items.push(n);
        }
        return order.map(key => ({
            key: key,
            app: byKey[key].app,
            relay: byKey[key].relay,
            items: byKey[key].items,
            count: byKey[key].items.length
        }));
    }

    function dismissGroup(key) {
        for (const g of groups)
            if (g.key === key) { for (const r of g.items.slice()) dismiss(r); return; }
    }

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

    function dismissUid(uid) { dismiss(byUid(uid)) }

    function dismiss(record) {
        if (!record) return;
        if (record.live && record.ref) {
            record.ref.dismiss();
        } else {
            restored = restored.filter(r => r.uid !== record.uid);
        }
        save();
    }

    function clearAll() {
        // Walks the RAW tracked list, not the rendered one. The rendered
        // list is sliced to maxRetained and used to be deduplicated, so
        // anything it was not showing survived a "clear all" and then
        // reappeared the moment its twin was gone. Copied first, because
        // dismissing mutates the model being walked.
        const model = server.trackedNotifications;
        const all = (model ? model.values : []).slice();
        for (const n of all) if (n) n.dismiss();
        restored = [];
        save();
    }

    // Deferred by a turn. Called straight from onNotification it ran before
    // the new notification was in trackedNotifications, so the file was
    // always one behind the screen - and the newest notification, the one
    // you most want back, was the one a restart lost.
    function save() { saveSoon.restart() }

    Timer {
        id: saveSoon
        interval: 0
        repeat: false
        onTriggered: {
            const flat = root.notifications.map(r => ({
                appName: r.appName, summary: r.summary, body: r.body,
                appIcon: r.appIcon, image: r.image
            }));
            store.setText(JSON.stringify(flat));
        }
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: notification => {
            // Transient means "show it, do not keep it": one per volume
            // keypress. Tracking those would walk a 50-entry centre full of
            // readings you only wanted at the moment you pressed the key,
            // and push the messages that matter off the end. It still goes
            // through `posted`, so the toast is unaffected.
            if (notification.transient) {
                if (!root.dnd) root.posted(root.recordFor(notification));
                return;
            }

            // Without this the notification is closed the moment this
            // handler returns and the centre never sees it.
            notification.tracked = true;

            if (!root.dnd) root.posted(root.recordFor(notification));

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
                let i = 0;
                for (const e of saved) {
                    out.push({
                        key: (e.appName || "") + "|" + (e.summary || "")
                             + "|" + (e.body || ""),
                        uid: "r" + (i++),
                        appName: e.appName || "",
                        summary: e.summary || "",
                        body: e.body || "",
                        appIcon: e.appIcon || "",
                        image: e.image || "",
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
