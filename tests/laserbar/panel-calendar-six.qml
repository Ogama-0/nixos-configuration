import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// The calendar pane, stubbed. August 2026 draws SIX rows.
//
// Not driven through CalendarModel: that one shells out to khal, so a render
// through it would assert on this machine's actual diary.
//
// Pane at 100,100, 526x420, uiScale 1. The events block is welded to the
// BOTTOM of the pane, so its top edge must land at the same y whatever the
// month's row count - that is the whole point of the pinning.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        CalendarPane {
            x: 100
            y: 100
            width: 526
            height: 420
            uiScale: 1
            monthLabel: "August 2026"
            onToday: false
            selectedLabel: "Tuesday 21 October"
            cells: [
                { day: 27, inMonth: false, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,6,27) },
                { day: 28, inMonth: false, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,6,28) },
                { day: 29, inMonth: false, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,6,29) },
                { day: 30, inMonth: false, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,6,30) },
                { day: 31, inMonth: false, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,6,31) },
                { day: 1, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,1) },
                { day: 2, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,2) },
                { day: 3, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,3) },
                { day: 4, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,4) },
                { day: 5, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,5) },
                { day: 6, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,6) },
                { day: 7, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,7) },
                { day: 8, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,8) },
                { day: 9, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,9) },
                { day: 10, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,10) },
                { day: 11, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,11) },
                { day: 12, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,12) },
                { day: 13, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,13) },
                { day: 14, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,14) },
                { day: 15, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,15) },
                { day: 16, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,16) },
                { day: 17, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,17) },
                { day: 18, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,18) },
                { day: 19, inMonth: true, isToday: true, isSelected: false, hasEvents: true, date: new Date(2026,7,19) },
                { day: 20, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,20) },
                { day: 21, inMonth: true, isToday: false, isSelected: true, hasEvents: true, date: new Date(2026,7,21) },
                { day: 22, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,22) },
                { day: 23, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,23) },
                { day: 24, inMonth: true, isToday: false, isSelected: false, hasEvents: true, date: new Date(2026,7,24) },
                { day: 25, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,25) },
                { day: 26, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,26) },
                { day: 27, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,27) },
                { day: 28, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,28) },
                { day: 29, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,29) },
                { day: 30, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,30) },
                { day: 31, inMonth: true, isToday: false, isSelected: false, hasEvents: false, date: new Date(2026,7,31) }
            ]
            events: [ { "start-time": "09:00", "title": "Cours B1 - algorithmique", "all-day": "False" },
                      { "start-time": "12:30", "title": "Dejeuner avec Marie", "all-day": "False" },
                      { "start-time": "14:00", "title": "Point hebdo equipe", "all-day": "False" },
                      { "start-time": "19:00", "title": "Repetition harmonie", "all-day": "False" } ]
        }
    }
}
