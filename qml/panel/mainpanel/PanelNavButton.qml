import QtQuick
import QtQuick.Shapes

// A month arrow. Small enough that an icon name and a tooltip would be more
// machinery than the thing itself.
Item {
    id: root

    property real uiScale: 1
    property string glyph: "left"

    signal activated

    width: 24 * uiScale
    height: 24 * uiScale

    Rectangle {
        anchors.fill: parent
        radius: 7 * root.uiScale
        color: area.containsMouse ? "@plateBg@" : "transparent"
    }

    Shape {
        anchors.fill: parent
        transform: [
            Scale { xScale: root.uiScale; yScale: root.uiScale },
            Translate { x: root.width / 2; y: root.height / 2 }
        ]
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: area.containsMouse ? "@clockColor@" : "@mutedColor@"
            strokeWidth: 1.9
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            // Both chevrons declared, one shown: a ShapePath whose data can
            // change is the silent-blank trap (adding-a-bar-widget rule 4).
            PathSvg { path: root.glyph === "left" ? "M 2 -5 L -3 0 L 2 5"
                                                  : "M -2 -5 L 3 0 L -2 5" }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.activated()
    }
}
