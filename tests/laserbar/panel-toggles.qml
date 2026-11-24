import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// The toggle grid on its own, with a stubbed list.
//
// Deliberately NOT driven through ControlPanel: the real ToggleModel reads
// nmcli, bluetoothctl, powerprofilesctl, swaymsg and darkman, so a render that
// went through it would assert on whatever this machine's radios and windows
// happened to be doing. The grid takes its list as a property precisely so it
// can be tested without any of that, and without a test-only hook inside the
// panel.
//
// Grid placed at 100,100 at uiScale 1. Content box 278x132: four columns of
// 62.75 on a 71.75 pitch, two rows of 61.5 on a 70.5 pitch.
//
// Eight tiles, one per cell - the lock no longer spans two columns, because
// the idle toggle took the cell that span used to eat. Any ninth tile needs a
// third row in ToggleGrid.qml first.
//
//   row 0  dnd(0)  profile(71.75)  night(143.5)  wifi(215.25)
//   row 1  bt(0)   idle(71.75)     lock(143.5)   dark(215.25)
//
// Screen x of a tile = 100 + col, y = 100 + row. Centres:
//   dnd     131,131   active   -> accent fill
//   profile 203,131   inactive -> plate fill
//   night   275,131   active
//   wifi    347,131   active
//   bt      131,201   inactive
//   idle    203,201   active   -> idle lock armed, nothing inhibiting
//   lock    275,201   action   -> no fill, outlined
//   dark    347,201   active
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
                { key: "idle",    icon: "eye",      name: "Idle lock on",   active: true },
                { key: "lock",    icon: "lock",     name: "Lock the screen", action: true },
                { key: "dark",    icon: "moon",     name: "Dark mode",      active: true }
            ]
        }
    }
}
