import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "common"
import "notification"

// The two rules urgency decides, and the relative-time wording.
//
// Critical must NOT expire: a battery at 3% that cleared itself after six
// seconds because you happened to be looking elsewhere is the one failure
// the whole surface exists to prevent. Low goes sooner than normal - a scan
// finishing is not a person.
//
// Driven through the pure predicates rather than by waiting out a timer.
Scope {
    NowClock { id: clock; active: true }

    NotificationToasts {
        id: toasts
        clock: clock
        Component.onCompleted: {
            console.log("EXPIRES_LOW      " + toasts.expires(NotificationUrgency.Low));
            console.log("EXPIRES_NORMAL   " + toasts.expires(NotificationUrgency.Normal));
            console.log("EXPIRES_CRITICAL " + toasts.expires(NotificationUrgency.Critical));
            console.log("LIFE_LOW_SHORTER "
                        + (toasts.lifeFor(NotificationUrgency.Low)
                           < toasts.lifeFor(NotificationUrgency.Normal)));

            const now = Date.now();
            const words = [
                clock.relative(0),
                clock.relative(now),
                clock.relative(now - 5 * 60000),
                clock.relative(now - 2 * 3600000),
                clock.relative(now - 3 * 86400000)
            ].join("|");
            console.log("RELATIVE " + words);

            const ok = toasts.expires(NotificationUrgency.Low)
                    && toasts.expires(NotificationUrgency.Normal)
                    && !toasts.expires(NotificationUrgency.Critical)
                    && words === "earlier|now|5m ago|2h ago|3d ago";
            console.log(ok ? "URGENCY ok" : "URGENCY WRONG " + words);
        }
    }
}
