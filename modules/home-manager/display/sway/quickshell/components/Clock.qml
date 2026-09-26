import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    property string clockText: ""
    property string dateText: ""
    property string tempText: "Paris  --°C"

    anchors {
        top: true
        right: true
    }
    margins {
        top: 24
        right: 24
    }

    implicitWidth: 440
    implicitHeight: 240
    color: "transparent"

    WlrLayershell.namespace: "clock-widget"
    WlrLayershell.layer: WlrLayer.Background

    Rectangle {
        anchors.fill: parent
        radius: 40
        color: "@cardBg@"
        border.color: "@cardBorder@"
        border.width: 2

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.clockText
                color: "@clockColor@"
                font.pixelSize: 64
                font.weight: Font.DemiBold
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.dateText
                color: "@dateColor@"
                font.pixelSize: 26
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 12
                Layout.preferredWidth: 240
                height: 2
                color: "@dividerColor@"
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 12
                text: root.tempText
                color: "@tempColor@"
                font.pixelSize: 30
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
            root.clockText = Qt.formatDateTime(now, "HH:mm:ss")
            root.dateText = Qt.formatDateTime(now, "dddd d MMMM")
        }
    }

    Process {
        id: weatherProc
        command: [
            "curl", "-s", "--max-time", "5",
            "https://api.open-meteo.com/v1/forecast?latitude=48.8566&longitude=2.3522&current=temperature_2m"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text)
                    root.tempText = "Paris  " + data.current.temperature_2m.toFixed(1) + "°C"
                } catch (e) {
                    root.tempText = "Paris  --°C"
                }
            }
        }
    }

    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: weatherProc.running = true
    }
}
