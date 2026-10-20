import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// Two pure decisions, driven from literals and asserted on the log.
//
// Neither can be reached through a render: one needs a notification flood on
// a real bus, the other needs geoclue and a passage of time. Both are places
// where getting it wrong is silent.
//
//   overflow()  - which notifications to retire when the ceiling is passed.
//                 The list it walks is the live model, and dismissing from it
//                 REMOVES entries, so walking it by index while mutating it
//                 skips half of them.
//
//   needsFix()  - whether to ask geoclue again. The laptop is meant to be
//                 followed; a location fetched once per session is a
//                 hardcoded city with extra steps.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
    }

    NotificationServer { id: server }
    WeatherModel { id: weather; active: false }

    Item {
        Component.onCompleted: {
            // A stand-in for the live model: dismiss() removes the entry,
            // which is exactly what trackedNotifications does.
            function makeLive(n) {
                const list = [];
                for (let i = 0; i < n; i++) {
                    const item = {
                        idx: i,
                        dismiss: function () {
                            const at = list.indexOf(this);
                            if (at >= 0) list.splice(at, 1);
                        }
                    };
                    list.push(item);
                }
                return list;
            }

            // The shape this used to be, kept so the bug stays pinned: walk
            // the live list by index while dismissing from it. The loop bound
            // shrinks under the cursor and half the excess survives.
            const naive = makeLive(56);
            for (let i = 0; i < naive.length - 50; i++)
                if (naive[i]) naive[i].dismiss();
            console.log("NAIVE retained=" + naive.length + " (wanted 50)");

            const live = makeLive(56);
            for (const doomed of server.overflow(live, 50)) doomed.dismiss();
            console.log("OVERFLOW retained=" + live.length
                        + " oldest=" + (live.length ? live[0].idx : -1));

            const hour = 3600000;
            const now = Date.now();
            console.log("RELOCATE never=" + weather.needsFix(NaN, now, hour)
                        + " fresh=" + weather.needsFix(48.8, now - hour / 2, hour)
                        + " stale=" + weather.needsFix(48.8, now - 2 * hour, hour));
        }
    }
}
