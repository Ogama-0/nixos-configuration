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
// `width` deliberately includes both flares. RevealMask clips on an x range,
// so a module sized to its body alone would have its flares revealed on a
// different schedule from the thing they are attached to.
Item {
    id: root

    required property real bodyWidth
    required property real bodyHeight
    property real radius: 9
    property real flare: 21
    property real outline: 4.6
    property color fillColor: "@capsuleFill@"

    // Half the stroke falls outside the path, so the item carries an
    // allowance for it on every side. Without this the capsule looks fine on
    // its own but loses the outer half of its outline the moment it is put
    // inside RevealMask, whose layer texture is exactly the item's size and
    // clips anything hanging over the edge.
    readonly property real inset: outline / 2

    readonly property real bodyX: inset + flare
    readonly property real centreY: height / 2

    width: bodyWidth + 2 * flare + outline
    height: bodyHeight + outline

    // Module content goes here, positioned against the item - so a consumer
    // offsets by bodyX to work in body coordinates.
    default property alias content: slot.data

    readonly property real tipPull: flare * 0.62
    // Shape-local, where the body occupies y 0..bodyHeight.
    readonly property real pathCentreY: bodyHeight / 2
    readonly property real ctrlTop: pathCentreY - (pathCentreY - radius) * 0.45
    readonly property real ctrlBottom: pathCentreY + ((bodyHeight - radius) - pathCentreY) * 0.45

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
            strokeColor: "@capsuleInk@"
            strokeWidth: root.outline
            joinStyle: ShapePath.RoundJoin

            startX: 0
            startY: root.pathCentreY

            // Left flare, up to the top-left corner's tangent.
            PathCubic {
                control1X: root.tipPull; control1Y: root.pathCentreY
                control2X: root.flare; control2Y: root.ctrlTop
                x: root.flare; y: root.radius
            }
            PathArc {
                x: root.flare + root.radius; y: 0
                radiusX: root.radius; radiusY: root.radius
                direction: PathArc.Clockwise
            }
            PathLine { x: root.flare + root.bodyWidth - root.radius; y: 0 }
            PathArc {
                x: root.flare + root.bodyWidth; y: root.radius
                radiusX: root.radius; radiusY: root.radius
                direction: PathArc.Clockwise
            }
            // Right flare, out to the tip and straight back in.
            PathCubic {
                control1X: root.flare + root.bodyWidth; control1Y: root.ctrlTop
                control2X: root.bodyWidth + 2 * root.flare - root.tipPull; control2Y: root.pathCentreY
                x: root.bodyWidth + 2 * root.flare; y: root.pathCentreY
            }
            PathCubic {
                control1X: root.bodyWidth + 2 * root.flare - root.tipPull; control1Y: root.pathCentreY
                control2X: root.flare + root.bodyWidth; control2Y: root.ctrlBottom
                x: root.flare + root.bodyWidth; y: root.bodyHeight - root.radius
            }
            PathArc {
                x: root.flare + root.bodyWidth - root.radius; y: root.bodyHeight
                radiusX: root.radius; radiusY: root.radius
                direction: PathArc.Clockwise
            }
            PathLine { x: root.flare + root.radius; y: root.bodyHeight }
            PathArc {
                x: root.flare; y: root.bodyHeight - root.radius
                radiusX: root.radius; radiusY: root.radius
                direction: PathArc.Clockwise
            }
            PathCubic {
                control1X: root.flare; control1Y: root.ctrlBottom
                control2X: root.tipPull; control2Y: root.pathCentreY
                x: 0; y: root.pathCentreY
            }
        }
    }

    Item {
        id: slot
        anchors.fill: parent
    }
}
