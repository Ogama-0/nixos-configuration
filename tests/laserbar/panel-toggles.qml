import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// The toggle grid on its own, with a stubbed list.
//
// Deliberately NOT driven through ControlPanel: the real ToggleModel reads
// nmcli, bluetoothctl, powerprofilesctl and darkman, so a render that went
// through it would assert on whatever this machine's radios happened to be
// doing. The grid takes its list as a property precisely so it can be tested
// without any of that, and without a test-only hook inside the panel.
//
// Grid placed at 100,100 at uiScale 1. Content box 278x132, four columns of
// 62 with 9 gaps, two rows of 61:
//
//   row 0  dnd(0)  profile(71)  night(142)  wifi(213)
//   row 1  bt(0)   lock(71, 133 wide)       dark(213)
//
// Screen x of a tile = 100 + col, y = 100 + row. Centres:
//   dnd     131,131   active   -> accent fill
//   profile 202,131   inactive -> plate fill
//   night   273,131   active
//   wifi    344,131   active
//   bt      131,201   inactive
//   lock    237,201   action   -> no fill, outlined
//   dark    344,201   active
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        ToggleGrid {
            x: 100
            y: 100
            width: 278
            height: 132
            uiScale: 1
            items: [
                { key: "dnd",     icon: "bell-off", name: "Do not disturb", active: true },
                { key: "profile", icon: "gauge",    name: "Balanced",       active: false },
                { key: "night",   icon: "warm",     name: "Night light",    active: true },
                { key: "wifi",    icon: "wifi",     name: "Wi-Fi",          active: true },
                { key: "bt",      icon: "bluetooth", name: "Bluetooth",     active: false },
                { key: "lock",    icon: "lock",     name: "Lock the screen", action: true },
                { key: "dark",    icon: "moon",     name: "Dark mode",      active: true }
            ]
        }
    }
}
