import QtQuick
import Quickshell
import "notification"

// What do-not-disturb does and does not silence.
//
// The rule is "everything except the system's own readings": a text or a
// BeReal must not interrupt you, but the volume keys still have to say what
// they did - this laptop has no volume LED, and a DND that silenced them
// would mean "stop telling me what the volume is".
//
// Driven through shouldPost() rather than through the bus. Nothing can send
// a notification from a fixture, which is why the rule is a pure function in
// the first place.
Scope {
    NotificationServer {
        id: server
        Component.onCompleted: {
            // transient = the system reading (volume, mic). Always through.
            console.log("DND_OFF_SYSTEM  " + server.shouldPost(true, false));
            console.log("DND_ON_SYSTEM   " + server.shouldPost(true, true));
            // Everything else: a person, an app, the phone.
            console.log("DND_OFF_OTHER   " + server.shouldPost(false, false));
            console.log("DND_ON_OTHER    " + server.shouldPost(false, true));

            const want = "true true true false";
            const got = [server.shouldPost(true, false),
                         server.shouldPost(true, true),
                         server.shouldPost(false, false),
                         server.shouldPost(false, true)].join(" ");
            console.log(got === want ? "DND_RULE ok" : "DND_RULE WRONG " + got);
        }
    }
}
