import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// A machine with no GPU telemetry at all.
//
// The assertion is not on pixels: it is that the model probes ONCE and then
// stops. This box has both an nvidia card and amdgpu, so a session booted on
// one of them would otherwise fork a doomed process every tick, forever.
// The model says so exactly once, and that line in the log is the test.
//
// Both seams point at things that cannot exist, and the tick is fast enough
// that the harness's two-second settle covers several of them.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        MetricsModel {
            id: metrics
            active: true
            intervalMs: 300
            nvidiaSmi: "/nonexistent/nvidia-smi"
            amdBusyPath: "/nonexistent/gpu_busy_percent"
        }

        MetricsPane {
            x: 100; y: 100; width: 354; height: 90
            uiScale: 1
            cpuPct: metrics.cpuPct
            gpuPct: metrics.gpuPct
            ramPct: metrics.ramPct
        }
    }
}
