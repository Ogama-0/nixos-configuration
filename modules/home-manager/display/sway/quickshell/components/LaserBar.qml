import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: root

    property bool active: false
    property real batteryFraction: 0.5

    IpcHandler {
        target: "laserbar"
        function show(): void { root.active = true }
        function hide(): void { root.active = false }
    }

    Process {
        id: batteryProc
        command: ["bash", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseFloat(this.text.trim())
                root.batteryFraction = isNaN(value) ? 0.5 : value / 100
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: batteryProc.running = true
    }

    PanelWindow {
        id: panel

        anchors {
            top: true
            left: true
            right: true
        }
        implicitHeight: 64
        color: "transparent"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}

        WlrLayershell.namespace: "laser-bar"
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            id: leftBeam
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: 5
            radius: height / 2
            width: root.active ? root.batteryFraction * panel.width : 0
            Behavior on width {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: "@laserColor@" }
            }
        }

        Rectangle {
            id: rightBeam
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 5
            radius: height / 2
            width: root.active ? (1 - root.batteryFraction) * panel.width : 0
            Behavior on width {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "@laserColor@" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        Rectangle {
            id: flare
            width: 14
            height: 14
            radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: root.batteryFraction * panel.width - width / 2
            color: "@laserColor@"
            opacity: root.active ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 24
            }
        }

        RevealMask {
            id: clockReveal
            coverLeft: leftBeam.width
            coverRight: rightBeam.width
            panelWidth: panel.width
            width: 220
            height: 56
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "@cardBg@"
                border.color: "@cardBorder@"
                border.width: 2

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        id: clockText
                        Layout.alignment: Qt.AlignHCenter
                        color: "@clockColor@"
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }

                    Text {
                        id: dateText
                        Layout.alignment: Qt.AlignHCenter
                        color: "@dateColor@"
                        font.pixelSize: 12
                    }
                }
            }
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                const now = new Date()
                clockText.text = Qt.formatDateTime(now, "HH:mm:ss")
                dateText.text = Qt.formatDateTime(now, "dddd d MMMM")
            }
        }
    }
}
