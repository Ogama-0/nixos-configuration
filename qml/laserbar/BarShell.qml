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

    // 1080p-equivalent pixels, multiplied by this. See LaserBar.uiScale.
    property real uiScale: 1

    required property real bodyWidth
    required property real bodyHeight
    // Long and shallow: the taper reads as the beam narrowing into the module
    // rather than a bracket stuck on its end.
    //
    // Scaled, like every other dimension here. Left unscaled it was the only
    // one: on an unscaled 4K output the body, outline, edgeMargin, spacing
    // and BeamSide's pinchPad all doubled around a taper that did not, so
    // the flare read half-length and the pinch ramp - which is 20 * uiScale
    // and meant to match this - no longer agreed with the shape it ramps to.
    property real flare: 20 * uiScale
    property real outline: 4.6 * uiScale
    property color fillColor: "@capsuleFill@"
    // A dark border with a thin filament of the rail's colour running down
    // the middle of it. When the beams' meeting point falls inside this
    // module the filament changes colour at that point - that IS the
    // collision indicator, so nothing is drawn across the capsule.
    property color strokeColor: "@capsuleInk@"
    property color wireColor: "@capsuleInk@"
    property color wireColorAfterSeam: "@capsuleInk@"
    property real wireWidth: 1.5 * uiScale

    // Where the two beams collide, if that happens to fall inside this
    // module. Item-local x, or -1 for not here. The capsule then carries the
    // seam itself: one rail's colour up to the point, the other's after it,
    // and the collision burning white at the exact x - otherwise the payoff
    // would simply be hidden behind the capsule at some battery levels.
    property real seamX: -1
    readonly property bool seamed: seamX >= 0 && seamX <= width


    // An accent wash over part of the capsule - the focused workspace cell.
    // Clipped to an x range but drawn from the same path, so a cell at either
    // end carries its colour out into the flare and tapers with it.
    property color accentColor: "transparent"
    property real accentFromX: 0
    property real accentToX: 0

    readonly property real inset: outline / 2

    // The lip: the plate's end drawn out into an S that pinches to a narrow
    // waist and tapers into the wave. Not a shoulder reaching the band's
    // edges - that reads as two struts bolted on rather than the plate
    // flowing into the beam.
    property real neck: 7 * uiScale

    width: bodyWidth + 2 * flare + outline
    height: bodyHeight + outline

    readonly property real centreY: height / 2
    readonly property real bodyX: inset + flare
    readonly property real bodyY: inset
    readonly property real bodyRight: bodyX + bodyWidth

    // Module content goes here. Children are positioned against the item, so
    // a consumer offsets by bodyX / bodyY to work in body coordinates.
    default property alias content: slot.data

    // Control handles for the lip's S. Symmetric - horizontal where it leaves
    // the panel's flat edge and horizontal again at the waist, steepest in
    // between - so there is no corner anywhere along it. An asymmetric pair
    // leaves the lip flat for most of its length and then turning sharply.
    readonly property real lipPull: flare * 0.55
    readonly property real neckTop: centreY - neck / 2
    readonly property real neckBottom: centreY + neck / 2

    readonly property string topEdge: {
        const i = inset, bx = bodyX, br = bodyRight, bt = bodyY, hi = width - i;
        return "M " + i + " " + neckTop
            + " C " + (i + lipPull) + " " + neckTop + " " + (bx - lipPull) + " " + bt + " " + bx + " " + bt
            + " L " + br + " " + bt
            + " C " + (br + lipPull) + " " + bt + " " + (hi - lipPull) + " " + neckTop + " " + hi + " " + neckTop;
    }
    readonly property string bottomEdge: {
        const i = inset, bx = bodyX, br = bodyRight, bb = bodyY + bodyHeight, hi = width - i;
        return "M " + i + " " + neckBottom
            + " C " + (i + lipPull) + " " + neckBottom + " " + (bx - lipPull) + " " + bb + " " + bx + " " + bb
            + " L " + br + " " + bb
            + " C " + (br + lipPull) + " " + bb + " " + (hi - lipPull) + " " + neckBottom + " " + hi + " " + neckBottom;
    }

    // The plate follows the same two curves and closes across the waists, so
    // the white narrows with the lips instead of ending in a blunt rectangle.
    readonly property string pathData: {
        const i = inset, bx = bodyX, br = bodyRight;
        const bt = bodyY, bb = bodyY + bodyHeight, hi = width - i;
        return topEdge
            + " L " + hi + " " + neckBottom
            + " C " + (hi - lipPull) + " " + neckBottom + " " + (br + lipPull) + " " + bb + " " + br + " " + bb
            + " L " + bx + " " + bb
            + " C " + (bx - lipPull) + " " + bb + " " + (i + lipPull) + " " + neckBottom + " " + i + " " + neckBottom
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
            // Flat, not round: a round cap on a 4.6px dark stroke leaves a
            // dark blob closing off the tip of each lip. Flat lets the wire
            // run out open.
            capStyle: ShapePath.FlatCap
            PathSvg { path: root.topEdge }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.strokeColor
            strokeWidth: root.outline
            joinStyle: ShapePath.RoundJoin
            // Flat, not round: a round cap on a 4.6px dark stroke leaves a
            // dark blob closing off the tip of each lip. Flat lets the wire
            // run out open.
            capStyle: ShapePath.FlatCap
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
