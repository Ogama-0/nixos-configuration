import QtQuick
import Quickshell
import "components/panel"

// KDE Connect is a relay: everything the phone shows arrives under its
// name. Packing by sender would put a message, a battery warning and a
// BeReal in one stack labelled "KDE Connect".
//
// Driven through the REAL grouping code by seeding `restored`, which feeds
// the same `notifications` the bus does. The assertion is on the log.
Scope {
    NotificationServer {
        id: server
        Component.onCompleted: {
            server.restored = [
                { uid: "a", key: "k1", appName: "KDE Connect", summary: "Ogama phone",
                  body: "Ping!", live: false, ref: null },
                { uid: "b", key: "k2", appName: "KDE Connect", summary: "BeReal.",
                  body: "maelielsfr", live: false, ref: null },
                { uid: "c", key: "k3", appName: "KDE Connect", summary: "Ogama phone",
                  body: "Ping!", live: false, ref: null },
                { uid: "d", key: "k4", appName: "Signal", summary: "Marie",
                  body: "one", live: false, ref: null },
                { uid: "e", key: "k5", appName: "Signal", summary: "Marie",
                  body: "two", live: false, ref: null }
            ];
            const shape = server.groups.map(g => g.app + ":" + g.count).join(" ");
            console.log("GROUPS " + shape);

            // The Delete key's path: dismissUid removes exactly the one
            // selected and leaves its identical twin alone. "Ping!" from
            // the phone appears twice here on purpose.
            server.dismissUid("a");
            console.log("AFTER_DELETE " + server.notifications.length
                        + " remaining, uids "
                        + server.notifications.map(r => r.uid).join(","));
        }
    }
}
