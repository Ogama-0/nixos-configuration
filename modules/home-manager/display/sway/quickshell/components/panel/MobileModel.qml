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

    // { id, name, charge, charging, signal, network }. One phone: the zone
    // is a glance, not a device manager, and the second phone belongs in
    // the GUI.
    property var device: null
    readonly property bool connected: device !== null

    // The paired device, whether or not it is on the network right now.
    //
    // `kdeconnect-cli -a` below lists only REACHABLE devices, so a phone
    // that is asleep or off the wifi reports nothing - which is right for
    // the battery readout and wrong for everything that only needs to know
    // WHICH phone this is. Messages needs that to name its cached
    // conversations and find the contact cards; without it a phone going to
    // sleep took the whole message history with it.
    property string pairedId: ""
    property string pairedName: ""

    function openGui(): void { guiProc.running = true }

    // Pushes THIS machine's clipboard to the phone. The daemon reads the
    // clipboard itself, so there is no wl-paste in the way and nothing to
    // get wrong about selection ownership.
    function sendClipboard(): void {
        if (!device) return;
        clipProc.command = ["busctl", "--user", "call", "org.kde.kdeconnect",
            "/modules/kdeconnect/devices/" + device.id + "/clipboard",
            "org.kde.kdeconnect.device.clipboard", "sendClipboard"];
        clipProc.running = true;
    }

    // Picker first, then send. One shell because the second half depends on
    // the first and a cancelled picker must send nothing: zenity exits
    // non-zero, && stops, no file goes anywhere.
    function sendFile(): void {
        if (!device) return;
        fileProc.command = ["sh", "-c",
            "f=$(zenity --file-selection --title='Send to " + device.name
            + "') && exec kdeconnect-cli --device " + device.id
            + " --share \"$f\""];
        fileProc.running = true;
    }

    Process { id: clipProc }
    Process { id: fileProc }

    Process {
        id: guiProc
        command: ["kdeconnect-app"]
    }

    // Once at startup, not only while the zone is active. Messages listens
    // for incoming texts with the panel shut, and it cannot do that without
    // knowing which device it is listening about.
    Component.onCompleted: pairedProc.running = true

    // -l, not -a: every paired device, reachable or not.
    Process {
        id: pairedProc
        command: ["kdeconnect-cli", "-l", "--id-name-only"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = this.text.split("\n")
                    .map(l => l.trim())
                    .filter(l => l.length > 0)[0];
                if (!line) { root.pairedId = ""; root.pairedName = ""; return; }
                const sep = line.indexOf(" ");
                root.pairedId = sep < 0 ? line : line.slice(0, sep);
                root.pairedName = sep < 0 ? line : line.slice(sep + 1);
            }
        }
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
                    ? root.device
                    : { charge: -1, charging: false, signal: -1, network: "" };
                root.device = { id: id, name: name,
                                charge: keep.charge, charging: keep.charging,
                                signal: keep.signal, network: keep.network };
                root.readPlugins(id);
            }
        }
        onExited: exitCode => { if (exitCode !== 0) root.device = null }
    }

    // Each plugin is its own OBJECT under the device, not an interface on
    // it. The first version asked the device path for the battery interface
    // and silently got nothing, which looks identical to a phone with the
    // plugin switched off.
    function readPlugins(id) {
        const dev = "/modules/kdeconnect/devices/" + id;
        const get = (proc, obj, iface, prop) => {
            proc.command = ["busctl", "--user", "--json=short",
                "get-property", "org.kde.kdeconnect", dev + "/" + obj,
                "org.kde.kdeconnect.device." + iface, prop];
            proc.running = true;
        };
        get(chargeProc,   "battery", "battery", "charge");
        get(chargingProc, "battery", "battery", "isCharging");
        get(signalProc,   "connectivity_report", "connectivity_report",
            "cellularNetworkStrength");
        get(networkProc,  "connectivity_report", "connectivity_report",
            "cellularNetworkType");
    }

    function patch(field, value) {
        if (!root.device) return;
        const d = {
            id: root.device.id, name: root.device.name,
            charge: root.device.charge, charging: root.device.charging,
            signal: root.device.signal, network: root.device.network
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

    Process {
        id: signalProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = JSON.parse(this.text).data;
                    if (typeof v === "number") root.patch("signal", v);
                } catch (e) { /* no connectivity plugin */ }
            }
        }
    }

    Process {
        id: networkProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = JSON.parse(this.text).data;
                    if (typeof v === "string") root.patch("network", v);
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
        onTriggered: { listProc.running = true; pairedProc.running = true }
    }
}
