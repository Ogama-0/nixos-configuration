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

    // How far out the mouth opens, past the pinch point, and how tall it gets
    // there. The border leaves the capsule, pinches to a point, then opens to
    // the full height of the beam band - so the border itself forms the
    // funnel the beam pours through, instead of stopping at a tip.
    property real mouth: 30
    property real mouthHeight: 44

    width: bodyWidth + 2 * (flare + mouth) + outline
    height: Math.max(bodyHeight, mouthHeight) + outline

    readonly property real centreY: height / 2
    readonly property real bodyX: inset + mouth + flare
    readonly property real bodyY: (height - bodyHeight) / 2
    readonly property real bodyRight: bodyX + bodyWidth

    // Module content goes here. Children are positioned against the item, so
    // a consumer offsets by bodyX / bodyY to work in body coordinates.
    default property alias content: slot.data

    // Shoulder control points. Each shoulder is ONE smooth S from the band's
    // lip to the body's corner - no pinch in between. A pinch makes the top
    // and bottom shoulders meet at the centreline and cross into an X.
    readonly property real shoulderOut: mouth * 0.62
    readonly property real shoulderIn: flare * 0.55
    readonly property real mouthTop: centreY - mouthHeight / 2
    readonly property real mouthBottom: centreY + mouthHeight / 2

    readonly property string topEdge: {
        const i = inset, r = radius, bx = bodyX, br = bodyRight, bt = bodyY;
        const lo = i, hi = width - i;
        return "M " + lo + " " + mouthTop
            + " C " + (lo + shoulderOut) + " " + mouthTop + " " + (bx - shoulderIn) + " " + (bt + r) + " " + bx + " " + (bt + r)
            + " A " + r + " " + r + " 0 0 1 " + (bx + r) + " " + bt
            + " L " + (br - r) + " " + bt
            + " A " + r + " " + r + " 0 0 1 " + br + " " + (bt + r)
            + " C " + (br + shoulderIn) + " " + (bt + r) + " " + (hi - shoulderOut) + " " + mouthTop + " " + hi + " " + mouthTop;
    }
    readonly property string bottomEdge: {
        const i = inset, r = radius, bx = bodyX, br = bodyRight, bb = bodyY + bodyHeight;
        const lo = i, hi = width - i;
        return "M " + lo + " " + mouthBottom
            + " C " + (lo + shoulderOut) + " " + mouthBottom + " " + (bx - shoulderIn) + " " + (bb - r) + " " + bx + " " + (bb - r)
            + " A " + r + " " + r + " 0 0 0 " + (bx + r) + " " + bb
            + " L " + (br - r) + " " + bb
            + " A " + r + " " + r + " 0 0 0 " + br + " " + (bb - r)
            + " C " + (br + shoulderIn) + " " + (bb - r) + " " + (hi - shoulderOut) + " " + mouthBottom + " " + hi + " " + mouthBottom;
    }

    // The plate is simply the body: the shoulders are border, not plate.
    readonly property string pathData: {
        const r = radius, bx = bodyX, br = bodyRight, bt = bodyY, bb = bodyY + bodyHeight;
        return "M " + bx + " " + (bt + r)
            + " A " + r + " " + r + " 0 0 1 " + (bx + r) + " " + bt
            + " L " + (br - r) + " " + bt
            + " A " + r + " " + r + " 0 0 1 " + br + " " + (bt + r)
            + " L " + br + " " + (bb - r)
            + " A " + r + " " + r + " 0 0 1 " + (br - r) + " " + bb
            + " L " + (bx + r) + " " + bb
            + " A " + r + " " + r + " 0 0 1 " + bx + " " + (bb - r)
            + " Z";
    }

    Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.fillColor
            strokeColor: "transparent"
            strokeWidth: 0
            PathSvg { path: root.pathData }
        }
    }

    // Accent wash over part of the plate - the focused workspace cell.
    Item {
        x: root.accentFromX
        width: Math.max(0, root.accentToX - root.accentFromX)
        y: 0
        height: root.height
        clip: true
        visible: width > 0

        Shape {
            x: -root.accentFromX
            width: root.width
            height: root.height
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
        anchors.fill: parent
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
            x: -root.seamX
            y: 0
            width: root.width
            height: root.height
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
