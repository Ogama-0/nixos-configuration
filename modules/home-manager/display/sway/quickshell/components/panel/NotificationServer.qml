import QtQuick
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
Item {
    id: root

    // Suppresses nothing today, because nothing pops. It is here so the
    // toggle has somewhere real to write, and so toasts inherit it.
    property bool dnd: false

    // A desktop can emit notifications faster than anyone dismisses them.
    // Without a ceiling the list is an unbounded allocation driven by other
    // people's software.
    readonly property int maxRetained: 50

    readonly property var notifications: {
        const model = server.trackedNotifications;
        const all = model ? model.values : [];
        // Newest first: the list is read from the top.
        return all.slice().reverse().slice(0, root.maxRetained);
    }

    readonly property int count: notifications.length

    function dismiss(n) { if (n) n.dismiss() }

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

    function clearAll() {
        // Copied first: dismissing mutates the model being walked.
        const all = notifications.slice();
        for (const n of all) if (n) n.dismiss();
    }

    NotificationServer {
        id: server
        // Survive a quickshell restart without dropping what is on screen.
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
        }
    }
}
