import QtQuick
import Quickshell
import "common"
import "notification"

// What happens at the ceiling, and what "new" means.
//
// Five apps arrive with maxShown at 3. The toast that falls off the bottom
// must LEAVE - `leaving`, on its way through the exit animation - and not
// simply stop existing. It used to be sliced out of the array, which made it
// disappear between two frames and, worse, took any toast already mid-exit
// with it, cutting that animation off wherever it had got to.
//
// So the array is allowed to be longer than maxShown: what is capped is how
// many are ALIVE. The reaper clears the rest when their exit is done.
//
// Also asserts `arrive`, the flag that drives the fly-in. It replaced a
// `Date.now() - born < 150` test in the delegate, which was a race - the
// window closed whether or not a delegate had been built inside it. A new
// entry carries it; an entry carried over by toggle() or retire() does not,
// or expanding a pack would replay the whole arrival.
//
// Instantiates a PanelWindow, so this needs the render harness rather than
// the offscreen one - read the sentinels out of the .log beside the png,
// exactly as panel-notify-urgency.qml does.
Scope {
    NowClock { id: clock; active: true }

    NotificationToasts {
        id: toasts
        uiScale: 1
        clock: clock
        Component.onCompleted: {
            const now = Date.now();
            const send = app => toasts.show({
                appName: app, summary: app, body: "body",
                appIcon: "", image: "", ts: now
            });

            send("One");
            send("Two");
            send("Three");

            const alive = () => toasts.live.filter(t => !t.leaving).length;
            const leaving = () => toasts.live.filter(t => t.leaving).length;

            console.log("AT_CEILING   alive=" + alive() + " leaving=" + leaving());
            const atCeiling = alive() === 3 && leaving() === 0;

            // One past the ceiling. "One", the oldest, goes - but through
            // retire(), so it is still in the array with leaving set.
            send("Four");
            console.log("OVER_CEILING alive=" + alive() + " leaving=" + leaving());
            const over = alive() === 3 && leaving() === 1;

            const gone = toasts.live.filter(t => t.app === "One");
            console.log("OLDEST_LEAVES " + (gone.length === 1 && gone[0].leaving));
            const retired = gone.length === 1 && gone[0].leaving;

            // The one already on its way out must not be counted against
            // the ceiling, or a burst would show fewer toasts than it should.
            send("Five");
            console.log("BURST        alive=" + alive() + " leaving=" + leaving());
            const burst = alive() === 3;

            // ---- `arrive`, the flag that drives the fly-in ----
            //
            // Tested on entry() itself, because by the time anything out
            // here can look at `live` the flag is already gone: a Repeater
            // builds its delegates synchronously when the model is
            // reassigned, so show() has not returned before the first
            // delegate has consumed it. That is the mechanism working, and
            // it is also why it cannot be observed from a caller.
            const born = toasts.entry(1, [], "x", 0, 0, false, 0, true);
            const rebuilt = toasts.entry(1, [], "x", 0, 0, false, 0);
            console.log("ARRIVE       new=" + born.arrive
                        + " carriedOver=" + rebuilt.arrive);
            const arriveFlag = born.arrive === true && rebuilt.arrive === false;

            // ...and the other half: nothing left on screen is still
            // holding the flag, or every list change would re-fly every
            // toast on the desktop.
            const stuck = toasts.live.filter(t => t.arrive).length;
            console.log("ARRIVE_SPENT " + (stuck === 0));

            console.log(atCeiling && over && retired && burst
                        && arriveFlag && stuck === 0
                        ? "CEILING ok" : "CEILING WRONG");
        }
    }
}
