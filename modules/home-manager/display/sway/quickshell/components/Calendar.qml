import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    property string monthLabel: ""
    property var monthCells: []
    property int todayDayNum: 0
    property var upcomingEvents: []

    readonly property var weekdayLabels: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"]

    function rebuildMonth() {
        const now = new Date()
        root.todayDayNum = now.getDate()
        root.monthLabel = root.monthNames[now.getMonth()] + " " + now.getFullYear()

        const firstOfMonth = new Date(now.getFullYear(), now.getMonth(), 1)
        const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
        const firstWeekday = (firstOfMonth.getDay() + 6) % 7

        const cells = []
        for (let i = 0; i < firstWeekday; i++) cells.push(0)
        for (let d = 1; d <= daysInMonth; d++) cells.push(d)
        while (cells.length % 7 !== 0) cells.push(0)
        root.monthCells = cells
    }

    function eventDateTime(e) {
        if (e["all-day"] === "True") return new Date(e["start-date"] + "T00:00")
        return new Date(e["start-date"] + "T" + e["start-time"])
    }

    function eventLabel(e) {
        if (e["all-day"] === "True") return e["title"]
        return e["start-time"] + "  " + e["title"]
    }

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

    Timer {
        interval: 60 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.rebuildMonth()
    }

    Process {
        id: khalProc
        running: false
        command: [
            "khal", "list",
            "--json", "start-date", "--json", "start-time", "--json", "all-day",
            "--json", "title", "--json", "location",
            "today", "30d"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(l => l.trim().length > 0)
                let events = []
                for (const line of lines) {
                    try {
                        events = events.concat(JSON.parse(line))
                    } catch (e) {}
                }

                const now = new Date()
                const today = now.toISOString().slice(0, 10)
                events = events.filter(e => {
                    if (e["all-day"] === "True") return e["start-date"] >= today
                    return root.eventDateTime(e) >= now
                })
                events.sort((a, b) => root.eventDateTime(a) - root.eventDateTime(b))
                root.upcomingEvents = events.slice(0, 2)
            }
        }
    }

    Process {
        id: calendarSyncProc
        running: false
        command: ["vdirsyncer", "sync"]
        onExited: khalProc.running = true
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
        onTriggered: khalProc.running = true
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
