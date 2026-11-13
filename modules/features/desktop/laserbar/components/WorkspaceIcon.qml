import QtQuick
import QtQuick.Shapes

// Workspace icons as drawn geometry rather than font glyphs, so they stay
// crisp at 16px and carry the same weight as the capsule's own outline.
//
// Each icon is up to three stroked paths plus one filled path, declared
// statically. Deliberately not a Repeater over a path list: ShapePath is not
// an Item, so it cannot be a Repeater delegate - it fails silently, drawing
// nothing (BeamSide.qml documents the same trap).
//
// Coordinates are a 16x16 box centred on the origin.
Item {
    id: root

    required property string name
    property color color: "@capsuleInk@"
    property real thickness: 2.0
    property real uiScale: 1

    width: 16 * uiScale
    height: 16 * uiScale

    readonly property var art: {
        switch (name) {
        case "code":
            return { s: ["M -3.6 -4.4 L -7.6 0 L -3.6 4.4",
                         "M 3.6 -4.4 L 7.6 0 L 3.6 4.4",
                         "M 1.4 -5.4 L -1.4 5.4"], f: "" };
        case "web":
            return { s: ["M -5.8 0 A 5.8 5.8 0 1 1 5.8 0 A 5.8 5.8 0 1 1 -5.8 0",
                         "M -5.8 0 L 5.8 0",
                         "M 0 -5.8 C 3.1 -2.7 3.1 2.7 0 5.8 C -3.1 2.7 -3.1 -2.7 0 -5.8"], f: "" };
        case "chat":
            return { s: ["M -5.8 -3.8 L 5.8 -3.8 A 1.7 1.7 0 0 1 7.1 -2.1 L 7.1 1.6 A 1.7 1.7 0 0 1 5.8 3.3 L -1.3 3.3 L -4.1 5.8 L -4.1 3.3 L -5.8 3.3 A 1.7 1.7 0 0 1 -7.1 1.6 L -7.1 -2.1 A 1.7 1.7 0 0 1 -5.8 -3.8 Z",
                         "", ""], f: "" };
        case "music":
            return { s: ["M -1.1 4 L -1.1 -5 L 5.8 -6.5 L 5.8 1.7", "", ""],
                     f: "M -5.3 4 A 2.1 1.8 0 1 1 -1.1 4 A 2.1 1.8 0 1 1 -5.3 4 Z"
                        + " M 1.6 1.7 A 2.1 1.8 0 1 1 5.8 1.7 A 2.1 1.8 0 1 1 1.6 1.7 Z" };
        case "term":
            return { s: ["M -5.8 -3.4 L -1.6 0 L -5.8 3.4", "M 0.6 3.8 L 5.8 3.8", ""], f: "" };
        default:
            return { s: ["M -4.6 -3 A 1.6 1.6 0 0 1 -3 -4.6 L 3 -4.6 A 1.6 1.6 0 0 1 4.6 -3 L 4.6 3 A 1.6 1.6 0 0 1 3 4.6 L -3 4.6 A 1.6 1.6 0 0 1 -4.6 3 Z",
                         "", ""], f: "" };
        }
    }

    Shape {
        anchors.fill: parent
        antialiasing: true
        // The art is drawn around the origin, so without this its top-left
        // quadrant lands at negative coordinates - outside the Shape, and
        // clipped away by the cell that holds it.
        // The art is drawn around the origin in a 16x16 box, so it is scaled
        // into place and then shifted to the item's centre.
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
            strokeWidth: root.thickness * 0.8
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
