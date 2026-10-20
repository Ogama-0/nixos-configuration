import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// Every glyph, large, on the accent fill they are actually seen on.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        Row {
            x: 60; y: 200
            spacing: 18
            Repeater {
                model: ["bell", "bell-off", "leaf", "gauge", "bolt", "warm",
                        "wifi", "bluetooth", "moon", "sun", "speaker",
                        "speaker-muted", "lock", "phone", "clipboard", "upload"]
                Rectangle {
                    required property var modelData
                    width: 76; height: 76; radius: 18
                    color: "#FF27D796"
                    PanelIcon {
                        anchors.centerIn: parent
                        name: modelData
                        uiScale: 2.4
                        color: "#FF000000"
                    }
                }
            }
        }
    }
}
