import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    property string clockText: ""
    property string dateText: ""
    // Weather arrives from shell.qml, which owns the one model the session
    // shares. This used to be a curl of its own, hardcoded to Paris on a
    // 10-minute timer, printing that name wherever the laptop actually was.
    property real tempC: 0
    property string place: ""
    property bool weatherOk: false

    // The place is dropped until geoclue has answered, rather than guessed:
    // a temperature under the wrong city is worse than a temperature under
    // no city at all.
    readonly property string tempText:
        (place === "" ? "" : place + "  ")
        + (weatherOk ? tempC.toFixed(1) + "°C" : "--°C")

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

}
