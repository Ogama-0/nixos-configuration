import QtQuick
import Quickshell.Io

// The seven toggles and the system state behind them. Non-visual: it knows
// nothing about tiles or grids, the same split StatusModel.qml makes against
// StatusPanel.qml.
//
// EVERY poll is gated on `active`. This runs seven subprocesses a tick and
// the panel is shut most of the time; the bar's first non-negotiable rule
// applies here with more force than it does on the bar.
Item {
    id: root

    // Bound to the panel being open.
    property bool active: false

    // Do-not-disturb has no backend yet: Quickshell does not own the
    // notification bus until the notification task lands. Until then this is
    // the honest state of a thing that suppresses nothing.
    property bool dndOn: false

    property int profileIndex: 1          // 0 saver, 1 balanced, 2 performance
    property bool nightOn: false
    property bool wifiOn: false
    property bool btOn: false
    property bool darkOn: true

    signal lockRequested

    readonly property var profiles: [
        { id: "power-saver", icon: "leaf",  name: "Power saver" },
        { id: "balanced",    icon: "gauge", name: "Balanced" },
        { id: "performance", icon: "bolt",  name: "Performance" }
    ]

    // What the grid renders. Order here IS display order.
    readonly property var items: [
        { key: "dnd", icon: dndOn ? "bell-off" : "bell",
          name: dndOn ? "Do not disturb" : "Notifications on", active: dndOn },
        { key: "profile", icon: profiles[profileIndex].icon,
          name: profiles[profileIndex].name, active: profileIndex === 2 },
        { key: "night", icon: "warm", name: "Night light", active: nightOn },
        { key: "wifi", icon: "wifi", name: "Wi-Fi", active: wifiOn },
        { key: "bt", icon: "bluetooth", name: "Bluetooth", active: btOn },
        { key: "lock", icon: "lock", name: "Lock the screen", action: true },
        { key: "dark", icon: darkOn ? "moon" : "sun",
          name: darkOn ? "Dark mode" : "Light mode", active: darkOn }
    ]

    // ---------------- actions ----------------

    function act(key) {
        switch (key) {
        case "dnd":     dndOn = !dndOn; break;
        case "profile": setProfile((profileIndex + 1) % 3); break;
        case "night":   nightProc.toggle(!nightOn); break;
        case "wifi":    wifiProc.toggle(!wifiOn); break;
        case "bt":      btProc.toggle(!btOn); break;
        case "dark":    darkProc.toggle(); break;
        case "lock":    lockRequested(); break;
        }
    }

    function setProfile(i) {
        profileIndex = i;
        profileSet.command = ["powerprofilesctl", "set", profiles[i].id];
        profileSet.running = true;
    }

    Process { id: profileSet }

    // ---------------- readers ----------------
    //
    // Each reader owns its own setter so a backend that is missing leaves
    // exactly one toggle wrong rather than blanking the block.

    Process {
        id: profileRead
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                for (let i = 0; i < root.profiles.length; i++)
                    if (root.profiles[i].id === t) root.profileIndex = i;
            }
        }
    }

    Process {
        id: nightProc
        command: ["@systemctlBin@", "--user", "is-active", "gammastep.service"]
        function toggle(on) {
            nightSet.command = ["@systemctlBin@", "--user",
                                on ? "start" : "stop", "gammastep.service"];
            nightSet.running = true;
            root.nightOn = on;
        }
        stdout: StdioCollector {
            onStreamFinished: root.nightOn = this.text.trim() === "active"
        }
    }
    Process { id: nightSet }

    Process {
        id: wifiProc
        command: ["nmcli", "radio", "wifi"]
        function toggle(on) {
            wifiSet.command = ["nmcli", "radio", "wifi", on ? "on" : "off"];
            wifiSet.running = true;
            root.wifiOn = on;
        }
        stdout: StdioCollector {
            onStreamFinished: root.wifiOn = this.text.trim() === "enabled"
        }
    }
    Process { id: wifiSet }

    Process {
        id: btProc
        command: ["bluetoothctl", "show"]
        function toggle(on) {
            btSet.command = ["bluetoothctl", "power", on ? "on" : "off"];
            btSet.running = true;
            root.btOn = on;
        }
        stdout: StdioCollector {
            onStreamFinished: root.btOn = this.text.indexOf("Powered: yes") >= 0
        }
    }
    Process { id: btSet }

    Process {
        id: darkProc
        command: ["darkman", "get"]
        function toggle() {
            darkSet.running = true;
            root.darkOn = !root.darkOn;
        }
        stdout: StdioCollector {
            onStreamFinished: root.darkOn = this.text.trim() === "dark"
        }
    }
    Process {
        id: darkSet
        command: ["darkman", "toggle"]
    }

    // ---------------- the one scheduler ----------------

    Timer {
        // Only while the panel is up. These are radios and daemons; nothing
        // here changes while nobody is looking at it that we will not catch
        // on the next open.
        interval: 4000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            profileRead.running = true;
            nightProc.running = true;
            wifiProc.running = true;
            btProc.running = true;
            darkProc.running = true;
        }
    }
}
