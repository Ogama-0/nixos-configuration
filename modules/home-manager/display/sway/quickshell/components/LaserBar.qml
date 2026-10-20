import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.I3
import Quickshell.Networking

// The laser bar itself: battery-driven beams from each screen edge, a
// collision payoff where they meet, and whatever bar modules are listed at
// the bottom of PanelWindow. Beam/collision visuals live in BeamSide.qml
// and CollisionEffects.qml; each module is self-contained (see
// ClockModule.qml and, underneath it, GlassPill.qml for the shared
// template) - adding or removing one is a single block below, nothing
// elsewhere needs to change.
Scope {
    id: root

    property bool active: false
    property real batteryFraction: 0.5

    // Raised when the clock capsule is clicked. shell.qml owns the panel;
    // the bar only reports the click.
    signal panelRequested

    // Sway speaks the i3 IPC, so this is socket-driven: no swaymsg subprocess
    // and no polling. Sway destroys a workspace as soon as its last window
    // closes, so "the workspaces it reports" is already "the workspaces with
    // windows" - the swaybar question.
    //
    // Takes the screen, because each bar shows its own output's workspaces.
    function workspacesFor(screenName) {
        const out = [];
        const all = I3.workspaces ? I3.workspaces.values : [];
        for (let i = 0; i < all.length; i++) {
            const w = all[i];
            if (screenName && w.monitor && w.monitor.name !== screenName) continue;
            out.push({
                // Keyed on id, not number: sway reports number -1 for every
                // named workspace, so two of those collide on one key and the
                // strip loses track of which cell is which.
                id: w.id,
                number: w.number,
                // `active`, not `focused`: focused means active AND on the
                // focused monitor, so the bar on a second screen would never
                // highlight anything.
                focused: w.active,
                icon: root.iconFor(w.number)
            });
        }
        return out;
    }

    // NetworkManager over DBus, signal-driven: no `iw` poll loop.
    readonly property var wifiState: {
        const blank = { ssid: "", strength: 0, connected: false };
        const devs = Networking.devices ? Networking.devices.values : [];
        for (let i = 0; i < devs.length; i++) {
            const d = devs[i];
            if (d.type !== DeviceType.Wifi) continue;
            const nets = d.networks ? d.networks.values : [];
            for (let j = 0; j < nets.length; j++) {
                const n = nets[j];
                if (!n.connected) continue;
                // Absent or NaN must not reach the bar arithmetic.
                let strength = n.signalStrength;
                if (strength === undefined || isNaN(strength)) strength = 0;
                return { ssid: n.name, strength: strength, connected: true };
            }
            return blank;
        }
        return blank;
    }

    function iconFor(n) {
        switch (n) {
        case 1: case 2: return "code";
        case 3: return "web";
        case 4: return "chat";
        case 5: return "music";
        case 10: return "term";
        default: return "plain";
        }
    }

    IpcHandler {
        target: "laserbar"
        function reveal(): void { root.active = true }
        function hide(): void { root.active = false }
    }

    // The bar follows the modifier key exactly, and nothing else touches it.
    //
    // sway tracks the modifier itself for a `bar { mode hide; modifier ... }`
    // block (see the sway config) and broadcasts the result as
    // bar_state_update with visible_by_modifier. That block draws nothing -
    // it exists purely as this signal.
    //
    // Key bindings cannot do this: sway stops firing a modifier's --release
    // binding once it has been used as a modifier, so mod+key would leave the
    // bar up with no hide ever sent. Subscribing to the compositor's own view
    // of the key is the only exact correspondence available.
    //
    // One long-lived subscription, idle on a socket until sway writes to it.
    Process {
        id: modifierWatch
        running: true
        command: ["@swaymsgBin@", "-t", "subscribe", "-m", "[\"bar_state_update\"]"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                // A line arriving means the subscription is healthy.
                watchRestart.attempt = 0;
                if (line.indexOf("visible_by_modifier") === -1) return;
                root.active = JSON.parse(line).visible_by_modifier === true;
            }
        }
        // If the subscription dies the bar would be stuck at whatever it was
        // last told, so it goes down with it - and comes straight back up.
        // `running: true` is a one-off assignment, not a binding, so without
        // this relaunch a single exit leaves the bar unreachable for the whole
        // session. That is a real risk here: the service is restarted from
        // sway's own startup and can beat SWAYSOCK into the user environment.
        onExited: {
            root.active = false;
            watchRestart.restart();
        }
    }

    Timer {
        id: watchRestart
        // Backs off so a swaymsg that cannot connect at all does not spin.
        property int attempt: 0
        interval: Math.min(8000, 250 * Math.pow(2, attempt))
        repeat: false
        onTriggered: {
            attempt = Math.min(attempt + 1, 5);
            modifierWatch.running = true;
        }
    }

    Process {
        id: batteryProc
        // LASERBAR_FAKE_BATTERY stands in for the capacity file, in the same
        // unit (percent), so a headless render collides the beams at a fixed
        // x instead of wherever this machine happens to be charged to. Only
        // scripts/laserbar-preview.sh sets it.
        command: ["bash", "-c", "if [ -n \"$LASERBAR_FAKE_BATTERY\" ]; then echo \"$LASERBAR_FAKE_BATTERY\"; else cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseFloat(this.text.trim())
                root.batteryFraction = isNaN(value) ? 0.5 : value / 100
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: batteryProc.running = true
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel

            required property var modelData
            screen: modelData

            anchors {
                bottom: true
                left: true
                right: true
            }
            implicitHeight: 70 * uiScale
            color: "transparent"
            focusable: false
            exclusionMode: ExclusionMode.Ignore

            // The bar takes the pointer while it is revealed, and nothing
            // at all while it is not - that is what makes a widget's
            // BarButton clickable (see BarButton.qml).
            //
            // Deliberately the whole panel rather than a rect per button:
            // the regions would have to be mapped into panel coordinates
            // and kept in step with capsules that move as widgets resize,
            // for an input surface that is only alive while a key is held.
            // What it costs is that mod+click along the bottom 70px does
            // not drag a window while the bar is up, which is the same
            // trade any clickable bar makes.
            //
            // Keyboard focus is never taken (`focusable: false`), so the
            // held modifier keeps doing its job underneath.
            mask: Region {
                width: root.active ? panel.width : 0
                height: root.active ? panel.implicitHeight : 0
            }

            // Vertical centre of the whole bar. The beam band is 44px tall
            // (BeamSide draws it symmetrically about this line) and the
            // capsules are shorter than that, so the band's lower edge is
            // what sets the gap to the screen edge.
            readonly property real bottomPadding: 3 * uiScale

            // Everything on the bar is sized in 1080p-equivalent pixels and
            // multiplied by this. A compositor that scales a HiDPI output
            // hands us logical pixels and this stays 1; an unscaled 4K output
            // reports its full height, where without this the bar would be
            // correct but half the size it should be.
            //
            // Set LASERBAR_UI_SCALE to pin it, which is how the render tests
            // check a size without needing that display.
            readonly property real uiScale: {
                const forced = parseFloat(Quickshell.env("LASERBAR_UI_SCALE"));
                if (!isNaN(forced) && forced > 0) return forced;
                const h = screen ? screen.height : 1080;
                return Math.max(1, Math.min(3, h / 1080));
            }
            readonly property real beamY: implicitHeight - bottomPadding - 22 * uiScale

            // This output's workspaces.
            readonly property var workspaceList:
                root.workspacesFor(modelData ? modelData.name : "")

            // Where the two beams collide: the battery percentage.
            readonly property real batteryMeetX: root.batteryFraction * width


            // Current travel distance of each beam from its screen edge,
            // shared by the beams, the collision meeting point, and every
            // module's reveal-mask sync.
            property real leftExtent: root.active ? root.batteryFraction * width : 0
            property real rightExtent: root.active ? (1 - root.batteryFraction) * width : 0

            Behavior on leftExtent {
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }
            Behavior on rightExtent {
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }

            WlrLayershell.namespace: "laser-bar"
            WlrLayershell.layer: WlrLayer.Overlay

            BeamSide {
                side: "left"
                accentColor: "@greenColor@"
                active: root.active
                extent: panel.leftExtent
                panelWidth: panel.width
                beamY: panel.beamY
                uiScale: panel.uiScale
                pinchSpans: slots.moduleSpans
            }

            BeamSide {
                side: "right"
                accentColor: "@redColor@"
                active: root.active
                extent: panel.rightExtent
                panelWidth: panel.width
                beamY: panel.beamY
                uiScale: panel.uiScale
                pinchSpans: slots.moduleSpans
            }

            CollisionEffects {
                active: root.active
                meetX: root.batteryFraction * panel.width
                panelWidth: panel.width
                beamY: panel.beamY
                uiScale: panel.uiScale
            }

            // ── Modules ──────────────────────────────────────────────
            // Add or remove a module by adding/removing one block here. A
            // module says which side of the bar it belongs on and nothing
            // else: BarSlots places it on the beam and wires its reveal, so
            // size, position and the coverLeft/coverRight plumbing are not
            // the module's problem. See BarSlots.qml.

            BarSlots {
                id: slots
                panelWidth: panel.width
                beamY: panel.beamY
                uiScale: panel.uiScale
                coverLeft: panel.leftExtent
                coverRight: panel.rightExtent
                active: root.active
                leftRail: "@greenColor@"
                rightRail: "@redColor@"
                ink: "@capsuleInk@"
                meetX: panel.batteryMeetX

                // Three groups, each a capsule. A widget says which group it
                // is in and where in that group it sits, so adding one - a
                // DND button left of the clock, say - is a line here and a
                // file in components/.
                BarGroup {
                    slotSide: "left"
                    reservedBodyWidth: wsWidget.reservedWidth

                    WorkspaceWidget {
                        id: wsWidget
                        pos: 1
                        workspaces: panel.workspaceList
                    }
                }

                BarGroup {
                    slotSide: "centre"

                    ClockWidget {
                        pos: 1
                        onPanelRequested: root.panelRequested()
                    }
                }

                BarGroup {
                    slotSide: "right"

                    MusicWidget { pos: 1 }

                    WifiWidget {
                        pos: 2
                        ssid: root.wifiState.ssid
                        strength: root.wifiState.strength
                        connected: root.wifiState.connected
                    }
                }
            }
        }
    }
}
