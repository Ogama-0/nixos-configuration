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
    property real flare: 21
    property real outline: 4.6
    property color fillColor: "@capsuleFill@"

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
    // from the capsule it is washing.
    readonly property string pathData: {
        const f = flare, w = bodyWidth, h = bodyHeight, r = radius;
        const cy = pathCentreY, k = tipPull, ct = ctrlTop, cb = ctrlBottom;
        const rt = w + 2 * f;
        return "M 0 " + cy
            + " C " + k + " " + cy + " " + f + " " + ct + " " + f + " " + r
            + " A " + r + " " + r + " 0 0 1 " + (f + r) + " 0"
            + " L " + (f + w - r) + " 0"
            + " A " + r + " " + r + " 0 0 1 " + (f + w) + " " + r
            + " C " + (f + w) + " " + ct + " " + (rt - k) + " " + cy + " " + rt + " " + cy
            + " C " + (rt - k) + " " + cy + " " + (f + w) + " " + cb + " " + (f + w) + " " + (h - r)
            + " A " + r + " " + r + " 0 0 1 " + (f + w - r) + " " + h
            + " L " + (f + r) + " " + h
            + " A " + r + " " + r + " 0 0 1 " + f + " " + (h - r)
            + " C " + f + " " + cb + " " + k + " " + cy + " 0 " + cy
            + " Z";
    }

    Shape {
        x: root.inset
        y: root.inset
        width: root.bodyWidth + 2 * root.flare
        height: root.bodyHeight
        antialiasing: true
        // Same reason as the wave strands in BeamSide.qml: the default
        // renderer triangulates with no edge smoothing, CurveRenderer
        // antialiases on the GPU.
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

    Shape {
        x: root.inset
        y: root.inset
        width: root.bodyWidth + 2 * root.flare
        height: root.bodyHeight
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: "@capsuleInk@"
            strokeWidth: root.outline
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.pathData }
        }
    }

    Item {
        id: slot
        anchors.fill: parent
    }
}
