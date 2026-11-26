import QtQuick
import Quickshell.Io

// What is left on the disks that matter. Non-visual; DiskPane renders it.
//
// Only real block-device filesystems: df otherwise reports tmpfs, the nix
// store bind mounts and every /run/user/1000/doc gvfs mount, which is a
// column of noise rather than an answer to "can I still download this".
Item {
    id: root

    property bool active: false
    property var disks: []
    property string freeTotal: ""

    // Mounts worth a bar, in display order. Anything not mounted is skipped
    // rather than drawn empty.
    property var watched: ["/", "/home"]

    Process {
        id: dfProc
        command: ["df", "-B1", "--output=target,size,used,avail"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = {};
                for (const line of this.text.split("\n").slice(1)) {
                    const f = line.trim().split(/\s+/);
                    if (f.length < 4) continue;
                    rows[f[0]] = {
                        size: parseInt(f[1]),
                        used: parseInt(f[2]),
                        avail: parseInt(f[3])
                    };
                }

                const out = [];
                let free = 0;
                for (const m of root.watched) {
                    const r = rows[m];
                    if (!r || !(r.size > 0)) continue;
                    out.push({
                        mount: m,
                        label: m === "/" ? "/" : m.replace(/^\//, ""),
                        usedFraction: r.used / r.size,
                        freeBytes: r.avail
                    });
                    free += r.avail;
                }
                root.disks = out;
                root.freeTotal = root.humanise(free) + " free";
            }
        }
    }

    function humanise(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let v = bytes, i = 0;
        while (v >= 1024 && i < units.length - 1) { v /= 1024; i += 1; }
        return (v >= 100 ? Math.round(v) : v.toFixed(1)) + " " + units[i];
    }

    Timer {
        // Disks fill slowly and df stats every mount; once a minute while
        // the panel is up is already generous.
        interval: 60000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: dfProc.running = true
    }
}
