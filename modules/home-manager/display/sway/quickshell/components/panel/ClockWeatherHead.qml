import QtQuick

// Time, date and weather, across the top of the calendar zone.
//
// Orbitron for the readouts because that is already the bar clock's voice,
// and the panel is the bar's own surface rather than a separate window.
//
// Every value arrives as a property. The head draws; Clock and WeatherModel
// decide.
Item {
    id: root

    property real uiScale: 1
    property string timeText: "--:--"
    property string dateText: ""

    property real tempC: 0
    property string condition: ""
    property string place: ""
    property bool ok: false
    // Shown in place of the temperature when there is nothing to show. An
    // empty quarter of the panel is not an answer to "offline".
    property string failure: ""

    Text {
        id: time
        x: 0
        y: 0
        text: root.timeText
        color: "@clockColor@"
        font.family: "Orbitron"
        font.pixelSize: Math.round(46 * root.uiScale)
        font.weight: Font.Bold
    }

    Text {
        x: 0
        y: time.y + time.height + 8 * root.uiScale
        text: root.dateText
        color: "@dateColor@"
        font.pixelSize: Math.round(13 * root.uiScale)
    }

    // ---- weather, right-aligned ----

    PanelIcon {
        id: wxIcon
        name: root.ok ? "sun" : "bell-off"
        visible: root.ok
        uiScale: root.uiScale * 1.25
        color: "@greenColor@"
        x: temp.x - width - 11 * root.uiScale
        y: 2 * root.uiScale
    }

    Text {
        id: temp
        text: root.ok ? Math.round(root.tempC) + "°" : "—"
        color: "@clockColor@"
        font.family: "Orbitron"
        font.pixelSize: Math.round(26 * root.uiScale)
        font.weight: Font.DemiBold
        x: root.width - width
        y: 0
    }

    Text {
        id: wxWord
        text: root.ok
            ? (root.place === "" ? root.condition
                                 : root.condition + " · " + root.place)
            : root.failure
        color: "@dateColor@"
        font.pixelSize: Math.round(12 * root.uiScale)
        x: root.width - width
        y: temp.y + temp.height + 3 * root.uiScale
    }
}
