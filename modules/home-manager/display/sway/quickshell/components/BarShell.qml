import QtQuick
import QtQuick.Shapes

// The shared chassis for every laser-bar module: a rounded capsule whose two
// ends flare out into the beam, so the wire opens into the module and becomes
// its outline rather than stopping at it.
//
// Drawn as ONE closed path, filled and stroked once. Two things that look like
// details are not:
//
//   - The flares are part of the filled shape. Filling only the body and
//     stroking the flares separately leaves a bare vertical edge between the
//     two flare curves, where the fill stops and nothing covers it.
//   - Each flare's control points sit on its endpoint's own axis: the first on
//     the wire's y, so the curve leaves the tip horizontally, the second on the
//     corner's x, so it arrives vertically, on the corner arc's tangent.
//     Landing inside the rounded corner instead leaves a visible step.
//
// `width` deliberately includes both flares and a half-stroke allowance on
// every side. RevealMask clips on an x range and its layer texture is exactly
// the item's size, so a module sized to its body alone would both lose the
// outer half of its outline and have its flares revealed on a different
// schedule from the capsule they belong to.
Item {
    id: root

    required property real bodyWidth
    required property real bodyHeight
    property real radius: 9
    // Long and shallow: the taper reads as the beam narrowing into the module
    // rather than a bracket stuck on its end.
    property real flare: 32
    property real outline: 4.6
    property color fillColor: "@capsuleFill@"
    // A dark border with a thin filament of the rail's colour running down
    // the middle of it. When the beams' meeting point falls inside this
    // module the filament changes colour at that point - that IS the
    // collision indicator, so nothing is drawn across the capsule.
    property color strokeColor: "@capsuleInk@"
    property color wireColor: "@capsuleInk@"
    property color wireColorAfterSeam: "@capsuleInk@"
    property real wireWidth: 1.5

    // Where the two beams collide, if that happens to fall inside this
    // module. Item-local x, or -1 for not here. The capsule then carries the
    // seam itself: one rail's colour up to the point, the other's after it,
    // and the collision burning white at the exact x - otherwise the payoff
    // would simply be hidden behind the capsule at some battery levels.
    property real seamX: -1
    readonly property bool seamed: seamX >= 0 && seamX <= width

    // The flare ends at the beam's own thickness, not at a point, and that
    // end is left unstroked. A flare closing to a point puts two strokes on
    // top of each other and the beam dead-ends into the resulting blob; an
    // open throat reads as two rails guiding the beam into the capsule.
    property real throat: 0

    // An accent wash over part of the capsule - the focused workspace cell.
    // Clipped to an x range but drawn from the same path, so a cell at either
    // end carries its colour out into the flare and tapers with it.
    property color accentColor: "transparent"
    property real accentFromX: 0
    property real accentToX: 0

    readonly property real inset: outline / 2
    readonly property real bodyX: inset + flare
    readonly property real centreY: height / 2

    width: bodyWidth + 2 * flare + outline
    height: bodyHeight + outline

    // Module content goes here. Children are positioned against the item, so a
    // consumer offsets by bodyX to work in body coordinates.
    default property alias content: slot.data

    readonly property real tipPull: flare * 0.62
    // Shape-local, where the body occupies y 0..bodyHeight.
    readonly property real pathCentreY: bodyHeight / 2
    readonly property real ctrlTop: pathCentreY - (pathCentreY - radius) * 0.45
    readonly property real ctrlBottom: pathCentreY + ((bodyHeight - radius) - pathCentreY) * 0.45

    // One source of truth for the outline, so the accent wash cannot drift
    // from the capsule it is washing. Split in three: a closed path for the
    // fill (which has to span the throats, or the capsule would leak), and
    // the top and bottom edges as separate OPEN paths for the stroke, so
    // nothing is ever drawn across a throat.
    readonly property string topEdge: {
        const f = flare, w = bodyWidth, r = radius, cy = pathCentreY, k = tipPull;
        const th = throat / 2, rt = w + 2 * f;
        return "M 0 " + (cy - th)
            + " C " + k + " " + (cy - th) + " " + f + " " + ctrlTop + " " + f + " " + r
            + " A " + r + " " + r + " 0 0 1 " + (f + r) + " 0"
            + " L " + (f + w - r) + " 0"
            + " A " + r + " " + r + " 0 0 1 " + (f + w) + " " + r
            + " C " + (f + w) + " " + ctrlTop + " " + (rt - k) + " " + (cy - th) + " " + rt + " " + (cy - th);
    }
    readonly property string bottomEdge: {
        const f = flare, w = bodyWidth, h = bodyHeight, r = radius, cy = pathCentreY, k = tipPull;
        const th = throat / 2, rt = w + 2 * f;
        return "M 0 " + (cy + th)
            + " C " + k + " " + (cy + th) + " " + f + " " + ctrlBottom + " " + f + " " + (h - r)
            + " A " + r + " " + r + " 0 0 0 " + (f + r) + " " + h
            + " L " + (f + w - r) + " " + h
            + " A " + r + " " + r + " 0 0 0 " + (f + w) + " " + (h - r)
            + " C " + (f + w) + " " + ctrlBottom + " " + (rt - k) + " " + (cy + th) + " " + rt + " " + (cy + th);
    }
    readonly property string pathData: {
        const f = flare, w = bodyWidth, h = bodyHeight, r = radius, cy = pathCentreY, k = tipPull;
        const th = throat / 2, rt = w + 2 * f;
        return topEdge
            + " L " + rt + " " + (cy + th)
            + " C " + (rt - k) + " " + (cy + th) + " " + (f + w) + " " + ctrlBottom + " " + (f + w) + " " + (h - r)
            + " A " + r + " " + r + " 0 0 1 " + (f + w - r) + " " + h
            + " L " + (f + r) + " " + h
            + " A " + r + " " + r + " 0 0 1 " + f + " " + (h - r)
            + " C " + f + " " + ctrlBottom + " " + k + " " + (cy + th) + " 0 " + (cy + th)
            + " Z";
    }

    Shape {
        x: root.inset
        y: root.inset
        width: root.bodyWidth + 2 * root.flare
        height: root.bodyHeight
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.fillColor
            strokeColor: "transparent"
            strokeWidth: 0
            PathSvg { path: root.pathData }
        }
    }

    // Accent wash, between fill and outline so the stroke still caps it.
    Item {
        x: root.inset + root.accentFromX
        width: Math.max(0, root.accentToX - root.accentFromX)
        y: root.inset
        height: root.bodyHeight
        clip: true
        visible: width > 0

        Shape {
            x: -(root.accentFromX)
            width: root.bodyWidth + 2 * root.flare
            height: root.bodyHeight
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: root.accentColor
                strokeColor: "transparent"
                strokeWidth: 0
                PathSvg { path: root.pathData }
            }
        }
    }

    // Outline, as two open edges so nothing is drawn across a throat: the
    // dark border first, then the filament down the middle of it.
    Shape {
        x: root.inset
        y: root.inset
        width: root.bodyWidth + 2 * root.flare
        height: root.bodyHeight
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.strokeColor
            strokeWidth: root.outline
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathSvg { path: root.topEdge }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.strokeColor
            strokeWidth: root.outline
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathSvg { path: root.bottomEdge }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.wireColor
            strokeWidth: root.wireWidth
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathSvg { path: root.topEdge }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.wireColor
            strokeWidth: root.wireWidth
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathSvg { path: root.bottomEdge }
        }
    }

    // Past the meeting point the filament takes the other rail's colour.
    // Only the filament is redrawn - the dark border is the same either side.
    Item {
        visible: root.seamed
        x: root.seamX
        width: Math.max(0, root.width - root.seamX)
        height: root.height
        clip: true

        Shape {
            x: root.inset - root.seamX
            y: root.inset
            width: root.bodyWidth + 2 * root.flare
            height: root.bodyHeight
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.wireColorAfterSeam
                strokeWidth: root.wireWidth
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathSvg { path: root.topEdge }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.wireColorAfterSeam
                strokeWidth: root.wireWidth
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathSvg { path: root.bottomEdge }
            }
        }
    }

    Item {
        id: slot
        anchors.fill: parent
    }
}
