import QtQuick
import Quickshell.Io

// CPU, GPU and RAM. Non-visual; MetricsPane renders it.
//
// -1 means "no reading", which is not the same as 0 and must not be drawn
// as one.
Item {
    id: root

    property bool active: false

    property int cpuPct: -1
    property int gpuPct: -1
    property int ramPct: -1
    property var cpuHistory: []

    // Seams, so a fixture can point them at something that does not exist
    // and watch what happens.
    property string nvidiaSmi: "nvidia-smi"
    property string amdBusyPath: "/sys/class/drm/card0/device/gpu_busy_percent"
    property int intervalMs: 2000

    // "unknown" until something answers; once "none", nothing is spawned
    // again. This machine has both an nvidia card and amdgpu, and a box
    // booted on one of them would otherwise fork a doomed process every
    // single tick for the whole session.
    property string gpuSource: "unknown"

    // ---------------- CPU, from /proc/stat deltas ----------------

    property real lastIdle: -1
    property real lastTotal: -1

    Process {
        id: cpuProc
        command: ["cat", "/proc/stat"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = this.text.split("\n")[0];
                const f = line.trim().split(/\s+/).slice(1).map(Number);
                if (f.length < 5) return;
                const idle = f[3] + (f[4] || 0);
                let total = 0;
                for (const v of f) total += v;

                if (root.lastTotal >= 0) {
                    const dT = total - root.lastTotal;
                    const dI = idle - root.lastIdle;
                    if (dT > 0) {
                        root.cpuPct = Math.round(100 * (dT - dI) / dT);
                        const h = root.cpuHistory.slice(-40);
                        h.push(root.cpuPct);
                        root.cpuHistory = h;
                    }
                }
                root.lastIdle = idle;
                root.lastTotal = total;
            }
        }
    }

    // ---------------- RAM, from /proc/meminfo ----------------

    Process {
        id: ramProc
        command: ["cat", "/proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const grab = k => {
                    const m = new RegExp(k + ":\\s+(\\d+)").exec(this.text);
                    return m ? parseInt(m[1]) : -1;
                };
                const total = grab("MemTotal");
                const avail = grab("MemAvailable");
                // MemAvailable, not MemFree: free counts the page cache as
                // used and reports a machine with a warm cache at 95%.
                if (total > 0 && avail >= 0)
                    root.ramPct = Math.round(100 * (total - avail) / total);
            }
        }
    }

    // ---------------- GPU ----------------

    // Attempts, counted here rather than inferred from exit codes. A
    // Process whose binary does not exist never emits onExited at all - it
    // fails to START - so give-up logic hung off exit never runs and the
    // model forks a doomed process every tick for the whole session. That
    // is not hypothetical: it is what the first version of this did, eight
    // times in two seconds, until the render test caught it.
    property int gpuAttempts: 0

    function probeGpu() {
        switch (root.gpuSource) {
        case "none":   return;
        case "nvidia": nvidiaProc.running = true; return;
        case "amd":    amdProc.running = true; return;
        }
        // Still unknown: one shot at each source, then stop for good.
        root.gpuAttempts += 1;
        if (root.gpuAttempts === 1) { nvidiaProc.running = true; return; }
        if (root.gpuAttempts === 2) { amdProc.running = true; return; }
        root.gpuSource = "none";
        root.gpuPct = -1;
        // Said once. This is the line that explains why the GPU row is a
        // dash; repeating it every two seconds would be its own bug.
        console.warn("laser-bar: no GPU telemetry, not probing again");
    }

    Process {
        id: nvidiaProc
        command: [root.nvidiaSmi,
                  "--query-gpu=utilization.gpu",
                  "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(this.text.trim());
                if (!isNaN(v)) {
                    root.gpuSource = "nvidia";
                    root.gpuPct = v;
                }
            }
        }
        // No onExited handler: a failed start never reaches one, and a
        // successful read is already handled above. The attempt counter in
        // probeGpu() is what moves this along.
    }

    Process {
        id: amdProc
        command: ["cat", root.amdBusyPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(this.text.trim());
                if (!isNaN(v)) {
                    root.gpuSource = "amd";
                    root.gpuPct = v;
                }
            }
        }

    }

    Timer {
        interval: root.intervalMs
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cpuProc.running = true;
            ramProc.running = true;
            root.probeGpu();
        }
    }
}
