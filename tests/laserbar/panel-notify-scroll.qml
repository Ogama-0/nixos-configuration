import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// Thirteen apps in a 400-tall zone - far more than fits. Before the list
// could scroll this rendered five plates and "and 8 more apps", and the
// other eight were unreachable. The render to look for: plates clipped at
// the bottom edge of the zone, nothing drawn past it, and the scroll
// indicator on the right once the list has been moved.
//
// Pane at 100,100, 262x400, uiScale 1.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        // NO empty input mask here, unlike the other panel fixtures: an
        // empty region makes the surface input-transparent, and this one
        // has to be dragged and wheeled to prove the list scrolls.
        WlrLayershell.layer: WlrLayer.Overlay

        NotificationPane {
            id: pane
            x: 100
            y: 100
            width: 262
            height: 400
            uiScale: 1

            // Part-way down, because the harness cannot deliver a wheel or
            // a drag. The nudge keeps the list "moving" so the scroll
            // indicator is still shown when grim fires a second later.
            scrollY: 300
            Timer {
                interval: 300; running: true; repeat: true
                onTriggered: pane.scrollY = pane.scrollY === 300 ? 302 : 300
            }

            // Discord open, so an expanded group of nine is in the scroll
            // too - that used to stop at six.
            expanded: ({ "Discord": true })

            groups: {
                const apps = ["Discord", "La Banque Postale", "Thunderbird",
                              "Aurora Store", "Finamp", "poweralertd",
                              "Syncthing", "Signal", "Element", "Nextcloud",
                              "KeePassXC", "Steam", "System"];
                const out = [];
                for (let a = 0; a < apps.length; a++) {
                    const n = a === 0 ? 9 : (a % 3) + 1;
                    const items = [];
                    for (let i = 0; i < n; i++)
                        items.push({ uid: apps[a] + ":" + i,
                                     appName: apps[a],
                                     summary: apps[a] + " message " + (i + 1),
                                     body: "BLACKOUT - Liste Epita #annonces "
                                           + "quelque chose de suffisamment "
                                           + "long pour etre coupe" });
                    out.push({ key: apps[a], app: apps[a],
                               count: n, items: items });
                }
                return out;
            }
        }
    }
}
