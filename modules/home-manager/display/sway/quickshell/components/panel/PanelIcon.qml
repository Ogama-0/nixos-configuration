import QtQuick
import QtQuick.Shapes

// Panel icons as drawn geometry, the same approach as WorkspaceIcon.qml and
// for the same reason: they stay crisp and carry the same weight as the
// sheet's own outline.
//
// Coordinates are a 24x24 box centred on the origin, so every path runs
// -12..12. Three stroked slots plus one filled slot, all declared statically
// - a ShapePath cannot be a Repeater delegate, it fails silently and draws
// nothing (BeamSide.qml and WorkspaceIcon.qml document the same trap).
//
// `name` CAN change at runtime - do-not-disturb flips its bell, the power
// profile cycles through three - and that is exactly the case rule 4 breaks:
// a ShapePath whose data changes after load draws wrongly or not at all. The
// first version reassigned `name` on a live Shape and the icon visibly
// smeared when you pressed the tile.
//
// So the Shape is built by a Loader that is torn down and rebuilt whenever
// the name changes. Every Shape therefore has constant path data for its
// whole life, which is the only arrangement that works.
Item {
    id: root

    required property string name
    property color color: "@mutedColor@"
    property real thickness: 1.7
    property real uiScale: 1

    width: 24 * uiScale
    height: 24 * uiScale

    readonly property var art: {
        switch (name) {
        case "bell":
            return { s: ["M -6 -2 A 6 6 0 0 1 6 -2 L 6 2 L 8 5 L -8 5 L -6 2 Z",
                         "M -2 8 A 2 2 0 0 0 2 8", ""], f: "" };
        case "bell-off":
            return { s: ["M -6 -4 A 6 6 0 0 1 3.3 -9",
                         "M -2 8 A 2 2 0 0 0 2 8",
                         "M -9 -9 L 9 9"], f: "" };
        // Power profiles. A leaf, a gauge, a bolt - three silhouettes that
        // cannot be mistaken for one another at 21px.
        case "leaf":
            return { s: ["M -8 8 C -8 -2 -2 -8 8 -8 C 8 2 2 8 -8 8 Z",
                         "M -8 8 C -4 4 -1 2 3 0", ""], f: "" };
        case "gauge":
            return { s: ["M -7 5.5 A 7 7 0 1 1 7 5.5",
                         "M 0 5.5 L 4 1", ""],
                     f: "M -1.2 5.5 A 1.2 1.2 0 1 1 1.2 5.5 A 1.2 1.2 0 1 1 -1.2 5.5 Z" };
        case "bolt":
            return { s: ["", "", ""],
                     f: "M 1 -9.5 L -6.5 1.5 L -2 1.5 L -3 9.5 L 4.5 -1.5 L 0 -1.5 Z" };
        // Night light. A sun shedding warm, wavy light - deliberately NOT a
        // crescent, because the crescent belongs to dark mode alone and the
        // two sit one tile apart.
        case "warm":
            return { s: ["M -3.6 -3.5 A 3.6 3.6 0 1 1 3.6 -3.5 A 3.6 3.6 0 1 1 -3.6 -3.5",
                         "M -8.5 3.5 C -7.1 2.3 -5.7 2.3 -4.3 3.5 C -2.9 4.7 -1.5 4.7 -0.1 3.5 C 1.3 2.3 2.7 2.3 4.1 3.5 C 5.5 4.7 6.9 4.7 8.3 3.5",
                         "M -8.5 7.6 C -7.1 6.4 -5.7 6.4 -4.3 7.6 C -2.9 8.8 -1.5 8.8 -0.1 7.6 C 1.3 6.4 2.7 6.4 4.1 7.6 C 5.5 8.8 6.9 8.8 8.3 7.6"],
                     f: "" };
        case "wifi":
            return { s: ["M -10 -3.5 A 16 16 0 0 1 10 -3.5",
                         "M -7 0 A 11 11 0 0 1 7 0",
                         "M -3.5 3.5 A 6 6 0 0 1 3.5 3.5"],
                     f: "M -1 7 A 1 1 0 1 1 1 7 A 1 1 0 1 1 -1 7 Z" };
        case "bluetooth":
            return { s: ["M -5 -5 L 5 5 L 0 9 L 0 -9 L 5 -5 L -5 5", "", ""], f: "" };
        case "moon":
            return { s: ["M 7 2.8 A 8 8 0 0 1 -2.8 -7 A 8 8 0 1 0 7 2.8 Z", "", ""], f: "" };
        case "sun":
            return { s: ["M -4 0 A 4 4 0 1 1 4 0 A 4 4 0 1 1 -4 0",
                         "M 0 -10 L 0 -7 M 0 7 L 0 10 M -10 0 L -7 0 M 7 0 L 10 0",
                         "M -7.1 -7.1 L -5 -5 M 5 5 L 7.1 7.1 M 7.1 -7.1 L 5 -5 M -5 5 L -7.1 7.1"],
                     f: "" };
        case "speaker":
            return { s: ["M 5 -4.5 A 5 5 0 0 1 5 4.5", "", ""],
                     f: "M -8 -3 L -4 -3 L 1 -8 L 1 8 L -4 3 L -8 3 Z" };
        case "speaker-muted":
            return { s: ["M 4 -4 L 9.5 4", "M 9.5 -4 L 4 4", ""],
                     f: "M -8 -3 L -4 -3 L 1 -8 L 1 8 L -4 3 L -8 3 Z" };
        case "lock":
            return { s: ["M -8 -2 L 8 -2 A 2 2 0 0 1 10 0 L 10 7 A 2 2 0 0 1 8 9 L -8 9 A 2 2 0 0 1 -10 7 L -10 0 A 2 2 0 0 1 -8 -2 Z",
                         "M -4 -2 L -4 -5 A 4 4 0 0 1 4 -5 L 4 -2", ""],
                     f: "" };
        }
        return { s: ["", "", ""], f: "" };
    }

    Loader {
        id: builder
        anchors.fill: parent
        sourceComponent: glyph

        Connections {
            target: root
            function onNameChanged() {
                // Tear down and rebuild: a reload is the point, not a cost.
                // These are eleven short paths, rebuilt only when a toggle
                // is actually pressed.
                builder.active = false;
                builder.active = true;
            }
        }
    }

    Component {
        id: glyph

        Shape {
            anchors.fill: parent
            transform: [
                Scale { xScale: root.uiScale; yScale: root.uiScale },
                Translate { x: root.width / 2; y: root.height / 2 }
            ]
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: root.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: root.art.s[0] }
            }
            ShapePath {
                strokeColor: root.color
                strokeWidth: root.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: root.art.s[1] }
            }
            ShapePath {
                strokeColor: root.color
                strokeWidth: root.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: root.art.s[2] }
            }
            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: root.color
                PathSvg { path: root.art.f }
            }
        }
    }
}
