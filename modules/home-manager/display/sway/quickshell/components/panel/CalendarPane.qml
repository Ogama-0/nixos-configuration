import QtQuick
// PanelBeam lives one directory up, with the rest of the panel's chrome.
import ".."

// The month, and what is on the day you picked.
//
// Everything arrives as properties so a fixture can drive it without khal
// being involved; CalendarModel.qml supplies the real ones.
//
// The events block is pinned to the BOTTOM and the slack collects above the
// divider. A month that draws six rows instead of five is otherwise enough
// to shove the whole list down by a row's height every time you page into
// one, which is the kind of movement you notice immediately.
Item {
    id: root

    property real uiScale: 1
    property string monthLabel: ""
    property var cells: []
    property var events: []
    property bool onToday: false
    property string selectedLabel: ""

    signal prevMonth
    signal nextMonth
    signal todayAsked
    signal daySelected(var date)

    readonly property real cellW: width / 7
    readonly property int shownEvents: 3
    readonly property int rows: Math.max(1, Math.ceil(cells.length / 7))

    // The grid takes the space rather than leaving a gap above the events.
    // A fixed row height left a band of dead glass between the last week and
    // the divider that got bigger in five-row months; filling it means the
    // calendar is the thing the zone is mostly made of, which is what it is
    // for. Floor keeps a six-row month from squeezing the numbers.
    readonly property real gridTop: dow.y + 19 * uiScale
    readonly property real gridBottom: eventsCol.y - 22 * uiScale
    readonly property real cellH:
        Math.max(26 * uiScale, (gridBottom - gridTop) / rows)

    // ---- month bar ----

    Item {
        id: monthBar
        x: 0; y: 0
        width: parent.width
        height: 26 * root.uiScale

        PanelNavButton {
            id: prev
            uiScale: root.uiScale
            glyph: "left"
            onActivated: root.prevMonth()
        }

        Text {
            id: monthName
            x: prev.width + 2 * root.uiScale
            // A fixed box, so the arrows do not shuffle sideways as the name
            // changes length between May and September.
            width: 150 * root.uiScale
            height: monthBar.height
            text: root.monthLabel
            color: "@clockColor@"
            font.pixelSize: Math.round(13.5 * root.uiScale)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        PanelNavButton {
            x: monthName.x + monthName.width + 2 * root.uiScale
            uiScale: root.uiScale
            glyph: "right"
            onActivated: root.nextMonth()
        }

        // Always on screen, dimming to inert once you are actually on today.
        // Revealing it only after you have navigated away means you have to
        // already be lost to find the way back.
        Rectangle {
            id: todayBtn
            x: monthBar.width - width
            y: (monthBar.height - height) / 2
            width: todayText.implicitWidth + 22 * root.uiScale
            height: 22 * root.uiScale
            radius: height / 2
            color: root.onToday ? "transparent" : "@plateBg@"
            border.width: root.onToday ? 0 : 1
            border.color: todayArea.containsMouse ? "@greenColor@" : "@glassBorder@"

            Text {
                id: todayText
                anchors.centerIn: parent
                text: "Today"
                color: root.onToday ? "@mutedColor@" : "@clockColor@"
                font.pixelSize: Math.round(11.5 * root.uiScale)
                font.weight: Font.Medium
            }

            MouseArea {
                id: todayArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.onToday
                onClicked: root.todayAsked()
            }
        }
    }

    // ---- weekday header ----

    Row {
        id: dow
        y: monthBar.height + 9 * root.uiScale
        Repeater {
            model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            Text {
                required property var modelData
                width: root.cellW
                height: 19 * root.uiScale
                text: modelData
                color: "@mutedColor@"
                font.pixelSize: Math.round(10.5 * root.uiScale)
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // ---- the grid ----

    Item {
        id: grid
        y: dow.y + 19 * root.uiScale
        width: parent.width
        height: root.rows * root.cellH

        // A discreet grid: one hairline under each week except the last, at
        // an alpha where you read it as structure rather than as lines.
        Repeater {
            model: root.rows - 1
            Rectangle {
                required property int index
                y: (index + 1) * root.cellH
                width: grid.width
                height: 1
                color: "@glassBorder@"
                opacity: 0.35
            }
        }

        Repeater {
            model: root.cells

            Item {
                required property var modelData
                required property int index

                x: (index % 7) * root.cellW
                y: Math.floor(index / 7) * root.cellH
                width: root.cellW
                height: root.cellH

                Rectangle {
                    anchors.centerIn: parent
                    // Capped, not tied to the row height: the rows grow to
                    // fill the zone and a pill that grew with them would be
                    // a 76px slab around a 13px number.
                    width: Math.min(parent.height - 2 * root.uiScale,
                                    34 * root.uiScale)
                    height: width
                    radius: 9 * root.uiScale
                    color: modelData.isSelected ? "@greenColor@"
                         : dayArea.containsMouse ? "@plateBg@" : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: modelData.day
                    color: modelData.isSelected ? "@onAccentInk@"
                         : !modelData.inMonth ? "@mutedColor@"
                         : modelData.isToday ? "@greenColor@" : "@clockColor@"
                    font.pixelSize: Math.round(12.5 * root.uiScale)
                    font.weight: modelData.isToday || modelData.isSelected
                        ? Font.DemiBold : Font.Normal
                }

                // A day carrying something gets a dot, so a busy week is
                // visible without clicking through it.
                //
                // Ink, not the accent. base0B in light is #94E1B0 and a 3px
                // dot of it on cream is invisible - the same rule that keeps
                // the toggles from carrying state in icon colour alone.
                Rectangle {
                    visible: modelData.hasEvents
                    width: 3 * root.uiScale
                    height: width
                    radius: width / 2
                    x: (parent.width - width) / 2
                    // Hung off the number, not the bottom of the cell -
                    // taller rows would otherwise strand it halfway to the
                    // row below.
                    y: parent.height / 2 + 11 * root.uiScale
                    color: modelData.isSelected ? "@onAccentInk@" : "@clockColor@"
                }

                MouseArea {
                    id: dayArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.daySelected(modelData.date)
                }
            }
        }
    }

    // ---- the day's events, welded to the bottom ----

    PanelBeam {
        id: evDivider
        horizontal: true
        x: 0
        y: eventsCol.y - 12 * root.uiScale
        width: root.width
    }

    Column {
        id: eventsCol
        y: root.height - height
        width: root.width
        spacing: 6 * root.uiScale

        Text {
            text: root.selectedLabel
            color: "@mutedColor@"
            font.pixelSize: Math.round(12 * root.uiScale)
            font.weight: Font.DemiBold
        }

        Text {
            visible: root.events.length === 0
            text: "Nothing on."
            color: "@mutedColor@"
            font.pixelSize: Math.round(12.5 * root.uiScale)
        }

        Repeater {
            model: root.events.slice(0, root.shownEvents)

            Item {
                required property var modelData
                width: eventsCol.width
                height: 18 * root.uiScale

                Rectangle {
                    width: 2 * root.uiScale
                    height: parent.height - 2 * root.uiScale
                    radius: width
                    color: "@greenColor@"
                }

                Text {
                    x: 10 * root.uiScale
                    width: 46 * root.uiScale
                    height: parent.height
                    text: modelData["all-day"] === "True"
                        ? "all day" : modelData["start-time"]
                    color: "@mutedColor@"
                    font.family: "Orbitron"
                    font.pixelSize: Math.round(11 * root.uiScale)
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    x: 62 * root.uiScale
                    width: parent.width - 62 * root.uiScale
                    height: parent.height
                    text: modelData["title"]
                    color: "@clockColor@"
                    font.pixelSize: Math.round(12.5 * root.uiScale)
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Text {
            visible: root.events.length > root.shownEvents
            text: "and " + (root.events.length - root.shownEvents) + " more"
            color: "@mutedColor@"
            font.pixelSize: Math.round(11.5 * root.uiScale)
        }
    }
}
