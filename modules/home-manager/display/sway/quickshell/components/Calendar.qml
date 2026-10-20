import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    // The khal reading and the month arithmetic live in CalendarModel, which
    // the panel's calendar pane renders too. One parser, two views.
    CalendarModel {
        id: cal
        active: true
        upcomingCount: 2
    }

    readonly property string monthLabel: cal.monthLabel
    // This renderer wants a flat list of day numbers with 0 for a blank, so
    // the shared cells are flattened here rather than changing the model for
    // one of its two consumers.
    readonly property var monthCells: cal.monthCells.map(c => c.inMonth ? c.day : 0)
    readonly property int todayDayNum: cal.today.getDate()
    readonly property var upcomingEvents: cal.upcomingEvents

    function eventLabel(e) { return cal.eventLabel(e) }

    readonly property var weekdayLabels: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"]

    anchors {
        top: true
        left: true
    }
    margins {
        top: 24
        left: 24
    }

    implicitWidth: 380
    implicitHeight: calContent.implicitHeight + 56
    color: "transparent"

    WlrLayershell.namespace: "calendar-widget"
    WlrLayershell.layer: WlrLayer.Background

    Process {
        id: calendarSyncProc
        running: false
        command: ["vdirsyncer", "sync"]
        onExited: cal.refresh()
    }

    Timer {
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: calendarSyncProc.running = true
    }

    Timer {
        interval: 2 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: cal.refresh()
    }

    Rectangle {
        anchors.fill: parent
        radius: 40
        color: "@cardBg@"
        border.color: "@cardBorder@"
        border.width: 2

        ColumnLayout {
            id: calContent
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 28
                rightMargin: 28
                topMargin: 28
            }
            spacing: 10

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.monthLabel
                color: "@clockColor@"
                font.pixelSize: 20
                font.weight: Font.DemiBold
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                columns: 7
                rowSpacing: 6
                columnSpacing: 0

                Repeater {
                    model: root.weekdayLabels
                    delegate: Text {
                        required property string modelData
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: "@dateColor@"
                        font.pixelSize: 12
                    }
                }

                Repeater {
                    model: root.monthCells
                    delegate: Item {
                        required property int modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.preferredHeight: 26

                        Rectangle {
                            anchors.centerIn: parent
                            visible: parent.modelData === root.todayDayNum
                            width: 24
                            height: 24
                            radius: 12
                            color: "@tempColor@"
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: parent.modelData !== 0
                            text: parent.modelData
                            color: parent.modelData === root.todayDayNum ? "@cardBg@" : "@clockColor@"
                            font.pixelSize: 13
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 8
                height: 2
                radius: 1
                color: "@dividerColor@"
            }

            Text {
                visible: root.upcomingEvents.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 8
                horizontalAlignment: Text.AlignHCenter
                text: "No upcoming events"
                color: "@dateColor@"
                font.pixelSize: 14
            }

            Repeater {
                model: root.upcomingEvents
                delegate: ColumnLayout {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.eventLabel(parent.modelData)
                        color: "@clockColor@"
                        font.pixelSize: 15
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !!parent.modelData["location"]
                        elide: Text.ElideRight
                        text: parent.modelData["location"] || ""
                        color: "@dateColor@"
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
