import QtQuick
import QtQuick.Shapes

// The centered time readout: a flat, slanted gray panel (not GlassPill's
// liquid-glass look - this one wants sharp edges and no glow), revealed in
// sync with the beams via RevealMask directly, same wiring GlassPill uses
// internally. Bold black time text in Orbitron - Corpta DEMO (the original
// requested font) turned out to have no digit/colon glyphs at all, so it
// can never render a clock; Orbitron is a properly-licensed, digit-complete
// stand-in with a similar futuristic/tech look, installed system-wide via
// pkgs/orbitron-font.nix (see font.nix) and referenced by family name
// (no FontLoader/file-path trick needed, unlike Corpta DEMO).
RevealMask {
    id: root

    required property bool active

    width: 120
    height: 32

    // See RevealMask.qml: root.x is panel-local only when this is a direct
    // child of the panel content, which it is here (LaserBar.qml places it
    // straight under PanelWindow), so no originXOverride needed.

    // The parallelogram is drawn as real skewed geometry (4 explicit
    // corners) rather than a `transform: Matrix4x4` shear on a plain
    // Rectangle - the transform approach fought with RevealMask's mask
    // clipping (which operates on the untransformed axis-aligned bounds),
    // chopping the shape into an L instead of a clean parallelogram.
    readonly property real shear: height * 0.35

    // Real rounded-corner geometry instead of an effect: a `layer.effect`
    // blur on this Shape (tried previously) didn't visibly change anything,
    // most likely some interaction with being nested inside RevealMask's
    // own masked/layered contentItem - rather than guess at a third effect
    // variant, this computes actual trimmed-edge + PathArc corners, the
    // same "plain Shape geometry, no transform, no layer" approach that
    // already renders correctly for the wave strands in BeamSide.qml.
    //
    // The parallelogram has two distinct interior angles (opposite corners
    // match, adjacent corners are supplementary), so only two trim
    // distances (d1, d2) are needed, derived from the standard
    // tangent-circle-in-a-corner formula: d = r / tan(angle / 2).
    readonly property real cornerRadius: 5
    readonly property real edgeLen: Math.sqrt(shear * shear + height * height)
    readonly property real ux: shear / edgeLen
    readonly property real uy: height / edgeLen
    readonly property real theta1: Math.acos(-ux)
    readonly property real theta2: Math.PI - theta1
    readonly property real d1: cornerRadius / Math.tan(theta1 / 2)
    readonly property real d2: cornerRadius / Math.tan(theta2 / 2)

    readonly property point topNearP0: Qt.point(shear + d1, 0)
    readonly property point topNearP1: Qt.point(width - d2, 0)
    readonly property point rightNearP1: Qt.point(width - d2 * ux, d2 * uy)
    readonly property point rightNearP2: Qt.point(width - shear + d1 * ux, height - d1 * uy)
    readonly property point bottomNearP2: Qt.point(width - shear - d1, height)
    readonly property point bottomNearP3: Qt.point(d2, height)
    readonly property point leftNearP3: Qt.point(d2 * ux, height - d2 * uy)
    readonly property point leftNearP0: Qt.point(shear - d1 * ux, d1 * uy)

    Shape {
        anchors.fill: parent
        antialiasing: true
        // The default GeometryRenderer triangulates and fills without any
        // edge smoothing (no MSAA here) - CurveRenderer (Qt 6.6+) renders
        // on the GPU with antialiasing built in, which is what was actually
        // missing; `antialiasing: true` alone doesn't change which
        // renderer backend is used.
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "#80808080"
            strokeColor: "#000000"
            strokeWidth: 6
            startX: root.topNearP0.x
            startY: root.topNearP0.y
            PathLine { x: root.topNearP1.x; y: root.topNearP1.y }
            PathArc { x: root.rightNearP1.x; y: root.rightNearP1.y; radiusX: root.cornerRadius; radiusY: root.cornerRadius; direction: PathArc.Clockwise }
            PathLine { x: root.rightNearP2.x; y: root.rightNearP2.y }
            PathArc { x: root.bottomNearP2.x; y: root.bottomNearP2.y; radiusX: root.cornerRadius; radiusY: root.cornerRadius; direction: PathArc.Clockwise }
            PathLine { x: root.bottomNearP3.x; y: root.bottomNearP3.y }
            PathArc { x: root.leftNearP3.x; y: root.leftNearP3.y; radiusX: root.cornerRadius; radiusY: root.cornerRadius; direction: PathArc.Clockwise }
            PathLine { x: root.leftNearP0.x; y: root.leftNearP0.y }
            PathArc { x: root.topNearP0.x; y: root.topNearP0.y; radiusX: root.cornerRadius; radiusY: root.cornerRadius; direction: PathArc.Clockwise }
        }
    }

    Text {
        id: clockText
        anchors.centerIn: parent
        color: "#000000"
        font.family: "Orbitron"
        font.pixelSize: 18
        font.bold: true
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "HH:mm")
    }
}
