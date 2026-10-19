import QtQuick
import Quickshell.Io

// The phone, over KDE Connect. Non-visual; MobilePane renders it.
//
// Two sources, because the CLI knows which devices exist and the daemon's
// DBus interface knows what they are doing:
//
//   kdeconnect-cli -a --id-name-only   reachable devices, as "<id> <name>"
//   org.kde.kdeconnect.device.battery  charge and charging state
//
// Nothing here is required to succeed. No daemon, no pairing, a phone that
// has wandered off the network and a build of KDE Connect that puts the
// battery somewhere else all land in the same place: `connected` false, or
// a device with `charge` -1. The pane says so rather than inventing a phone.
Item {
    id: root

    property bool active: false

    // { id, name, charge, charging }. One phone: the zone is a glance, not
    // a device manager, and the second phone belongs in the GUI.
    property var device: null
    readonly property bool connected: device !== null

    // The GUI is the whole point of the zone being clickable.
    function openGui(): void { guiProc.running = true }

    Process {
        id: guiProc
        command: ["kdeconnect-app"]
    }

    Process {
        id: listProc
        command: ["kdeconnect-cli", "-a", "--id-name-only"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = this.text.split("\n")
                    .map(l => l.trim())
                    .filter(l => l.length > 0)[0];
                if (!line) { root.device = null; return; }

                // "<id> <name>", and the name can contain spaces.
                const sep = line.indexOf(" ");
                const id = sep < 0 ? line : line.slice(0, sep);
                const name = sep < 0 ? line : line.slice(sep + 1);

                // Keep the charge we already had for this device rather than
                // flashing a dash every poll while the battery query is in
                // flight.
                const keep = root.device && root.device.id === id
                    ? root.device : { charge: -1, charging: false };
                root.device = { id: id, name: name,
                                charge: keep.charge, charging: keep.charging };
                root.readBattery(id);
            }
        }
        onExited: exitCode => { if (exitCode !== 0) root.device = null }
    }

    function readBattery(id) {
        const path = "/modules/kdeconnect/devices/" + id;
        chargeProc.command = ["busctl", "--user", "--json=short",
            "get-property", "org.kde.kdeconnect", path,
            "org.kde.kdeconnect.device.battery", "charge"];
        chargeProc.running = true;
        chargingProc.command = ["busctl", "--user", "--json=short",
            "get-property", "org.kde.kdeconnect", path,
            "org.kde.kdeconnect.device.battery", "isCharging"];
        chargingProc.running = true;
    }

    function patch(field, value) {
        if (!root.device) return;
        const d = {
            id: root.device.id, name: root.device.name,
            charge: root.device.charge, charging: root.device.charging
        };
        d[field] = value;
        root.device = d;
    }

    Process {
        id: chargeProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = JSON.parse(this.text).data;
                    if (typeof v === "number") root.patch("charge", v);
                } catch (e) { /* no battery plugin, or another layout */ }
            }
        }
    }

    Process {
        id: chargingProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = JSON.parse(this.text).data;
                    if (typeof v === "boolean") root.patch("charging", v);
                } catch (e) { /* as above */ }
            }
        }
    }

    Timer {
        // A phone appearing on the network is not urgent, and this is three
        // subprocesses a tick.
        interval: 10000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: listProc.running = true
    }
}
