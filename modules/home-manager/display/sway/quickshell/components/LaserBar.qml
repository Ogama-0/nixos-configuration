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

    // Sway speaks the i3 IPC, so this is socket-driven: no swaymsg subprocess
    // and no polling. Sway destroys a workspace as soon as its last window
    // closes, so "the workspaces it reports" is already "the workspaces with
    // windows" - the swaybar question.
    readonly property var workspaceList: {
        const out = [];
        const all = I3.workspaces ? I3.workspaces.values : [];
        for (let i = 0; i < all.length; i++) {
            const w = all[i];
            out.push({ number: w.number, focused: w.focused, icon: root.iconFor(w.number) });
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
                if (!n.active && !n.connected) continue;
                // Reported as a fraction by some backends and a percentage by
                // others; neither may reach the bar arithmetic as a NaN.
                let strength = n.signalStrength;
                if (strength === undefined || isNaN(strength)) strength = 0;
                if (strength > 1) strength = strength / 100;
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
            implicitHeight: 70
            color: "transparent"
            focusable: false
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}

            // Vertical centre of the whole bar. The beam band is 44px tall
            // (BeamSide draws it symmetrically about this line) and the
            // capsules are shorter than that, so the band's lower edge is
            // what sets the gap to the screen edge.
            readonly property real bottomPadding: 3
            readonly property real beamY: implicitHeight - bottomPadding - 22

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
                pinchSpans: slots.moduleSpans
            }

            BeamSide {
                side: "right"
                accentColor: "@redColor@"
                active: root.active
                extent: panel.rightExtent
                panelWidth: panel.width
                beamY: panel.beamY
                pinchSpans: slots.moduleSpans
            }

            CollisionEffects {
                active: root.active
                meetX: root.batteryFraction * panel.width
                panelWidth: panel.width
                beamY: panel.beamY
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
                coverLeft: panel.leftExtent
                coverRight: panel.rightExtent
                active: root.active
                leftRail: "@greenColor@"
                rightRail: "@redColor@"
                ink: "@capsuleInk@"
                meetX: panel.batteryMeetX

                WorkspaceModule { workspaces: root.workspaceList }

                ClockModule {}

                WifiModule {
                    ssid: root.wifiState.ssid
                    strength: root.wifiState.strength
                    connected: root.wifiState.connected
                }
            }
        }
    }
}
