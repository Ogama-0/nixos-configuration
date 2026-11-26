import QtQuick
import Quickshell
import Quickshell.Io

// The eight toggles and the system state behind them. Non-visual: it knows
// nothing about tiles or grids, the same split StatusModel.qml makes against
// StatusPanel.qml.
//
// EVERY poll is gated on `active`. This runs eight subprocesses a tick and
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

    // ---------------- idle ----------------
    //
    // Two independent reasons the machine will not lock or blank itself, and
    // the tile has to name which one is in force - "it just didn't lock" is
    // the state that wastes an afternoon of guessing.
    //
    //   idleOn        false when this tile has been switched off by hand.
    //   fullscreenOn  true while a visible window is fullscreen, which sway
    //                 turns into a real idle inhibit all on its own (the
    //                 `for_window [all] inhibit_idle fullscreen` in
    //                 sway/default.nix). Read-only here: nothing this panel
    //                 does can lift it, so the tile reports it rather than
    //                 pretending to own it.
    property bool idleOn: true
    property bool fullscreenOn: false

    // Written by this tile and nothing else; sway-idle.nix guards every
    // timeout command on its absence. $XDG_RUNTIME_DIR is read here rather
    // than baked in, because Process builds argv without a shell and would
    // pass the literal string through.
    readonly property string idleFlag:
        Quickshell.env("XDG_RUNTIME_DIR") + "/@idleInhibitFlag@"

    // Deliberately NOT what the tile toggles. Closing the lid locks the
    // session whatever this says - `before-sleep` is unguarded on purpose, so
    // switching idle off cannot turn into suspending to an unlocked desktop.
    // What this governs is the idle timeouts, which is why the labels say
    // "idle" and not "lock".
    readonly property bool idleHeldOff: !idleOn || fullscreenOn

    signal lockRequested

    readonly property var profiles: [
        { id: "power-saver", icon: "leaf",  name: "Power saver" },
        { id: "balanced",    icon: "gauge", name: "Balanced" },
        { id: "performance", icon: "bolt",  name: "Performance" }
    ]

    // What the grid renders. Order here IS display order: four to a row, and
    // there are exactly eight, so adding a ninth needs a third row in
    // ToggleGrid.qml and the height to put it in.
    readonly property var items: [
        { key: "dnd", icon: dndOn ? "bell-off" : "bell",
          name: dndOn ? "Do not disturb" : "Notifications on", active: dndOn },
        { key: "profile", icon: profiles[profileIndex].icon,
          name: profiles[profileIndex].name, active: profileIndex === 2 },
        { key: "night", icon: "warm", name: "Night light", active: nightOn },
        { key: "wifi", icon: "wifi", name: "Wi-Fi", active: wifiOn },
        { key: "bt", icon: "bluetooth", name: "Bluetooth", active: btOn },
        // Fullscreen wins the icon when it is in force, because it is the
        // state people are surprised by - the tile still reads "on" and the
        // screen still never locks. Switched off by hand is the eye with a
        // line through it; the two causes must not share a glyph.
        { key: "idle",
          icon: fullscreenOn ? "fullscreen" : (idleOn ? "eye" : "eye-off"),
          name: fullscreenOn
                  ? (idleOn ? "Fullscreen: idle lock held off"
                            : "Idle lock off, and fullscreen")
                  : (idleOn ? "Idle lock on" : "Idle lock off"),
          active: idleOn && !fullscreenOn },
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
        case "idle":    idleProc.toggle(!idleOn); break;
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

    // The flag file IS the state, read back rather than remembered: darkman
    // restarts this process on every dark/light switch, so anything held only
    // in a property here silently resets to its default a couple of times a
    // day. `test -e` and its exit code, not a file read, because the file is
    // empty by design - its existence is the whole payload.
    Process {
        id: idleProc
        command: ["test", "-e", root.idleFlag]
        function toggle(on) {
            // `on` means idle management is ON, so the inhibit flag has to go.
            idleSet.command = on ? ["rm", "-f", root.idleFlag]
                                 : ["touch", root.idleFlag];
            idleSet.running = true;
            root.idleOn = on;
        }
        onExited: code => root.idleOn = code !== 0
    }
    Process { id: idleSet }

    // Sway has no "am I idle-inhibited" query, so the inhibit has to be
    // re-derived from the thing that causes it: a fullscreen window that is
    // actually on screen.
    //
    // Only con and floating_con count. Workspace nodes carry
    // `fullscreen_mode: 1` of their own accord - every one of them, all the
    // time - so a walk that trusts that field alone reports the machine as
    // permanently fullscreen. `visible` narrows it to the workspace currently
    // on an output, which is the same condition sway's own
    // `inhibit_idle fullscreen` applies.
    function countFullscreen(text) {
        let n = 0;
        try {
            const walk = node => {
                if (!node) return;
                const t = node.type;
                if ((t === "con" || t === "floating_con")
                    && (node.fullscreen_mode || 0) > 0
                    && node.visible === true) n++;
                const kids = (node.nodes || []).concat(node.floating_nodes || []);
                for (let i = 0; i < kids.length; i++) walk(kids[i]);
            };
            walk(JSON.parse(text));
        } catch (e) {
            // A truncated or unparseable tree must not be read as "fullscreen",
            // which would label the tile with a cause that is not there.
            return 0;
        }
        return n;
    }

    Process {
        id: fullscreenProc
        command: ["@swaymsgBin@", "-t", "get_tree"]
        stdout: StdioCollector {
            onStreamFinished: root.fullscreenOn = root.countFullscreen(this.text) > 0
        }
    }

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
            idleProc.running = true;
            fullscreenProc.running = true;
            darkProc.running = true;
        }
    }
}
