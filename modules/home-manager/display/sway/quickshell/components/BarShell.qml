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

    readonly property real bodyX: flare
    readonly property real centreY: height / 2

    width: bodyWidth + 2 * flare
    height: bodyHeight

    // Module content goes here, positioned against the item - so a consumer
    // offsets by bodyX to work in body coordinates.
    default property alias content: slot.data

    readonly property real tipPull: flare * 0.62
    readonly property real ctrlTop: centreY - (centreY - radius) * 0.45
    readonly property real ctrlBottom: centreY + ((bodyHeight - radius) - centreY) * 0.45

    Shape {
        anchors.fill: parent
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
            startY: root.centreY

            // Left flare, up to the top-left corner's tangent.
            PathCubic {
                control1X: root.tipPull; control1Y: root.centreY
                control2X: root.bodyX; control2Y: root.ctrlTop
                x: root.bodyX; y: root.radius
            }
            PathArc {
                x: root.bodyX + root.radius; y: 0
                radiusX: root.radius; radiusY: root.radius
                direction: PathArc.Clockwise
            }
            PathLine { x: root.bodyX + root.bodyWidth - root.radius; y: 0 }
            PathArc {
                x: root.bodyX + root.bodyWidth; y: root.radius
                radiusX: root.radius; radiusY: root.radius
                direction: PathArc.Clockwise
            }
            // Right flare, out to the tip and straight back in.
            PathCubic {
                control1X: root.bodyX + root.bodyWidth; control1Y: root.ctrlTop
                control2X: root.width - root.tipPull; control2Y: root.centreY
                x: root.width; y: root.centreY
            }
            PathCubic {
                control1X: root.width - root.tipPull; control1Y: root.centreY
                control2X: root.bodyX + root.bodyWidth; control2Y: root.ctrlBottom
                x: root.bodyX + root.bodyWidth; y: root.bodyHeight - root.radius
            }
            PathArc {
                x: root.bodyX + root.bodyWidth - root.radius; y: root.bodyHeight
                radiusX: root.radius; radiusY: root.radius
                direction: PathArc.Clockwise
            }
            PathLine { x: root.bodyX + root.radius; y: root.bodyHeight }
            PathArc {
                x: root.bodyX; y: root.bodyHeight - root.radius
                radiusX: root.radius; radiusY: root.radius
                direction: PathArc.Clockwise
            }
            PathCubic {
                control1X: root.bodyX; control1Y: root.ctrlBottom
                control2X: root.tipPull; control2Y: root.centreY
                x: 0; y: root.centreY
            }
        }
    }

    Item {
        id: slot
        anchors.fill: parent
    }
}
