import QtQuick
import QtQuick.Shapes

// The panel's silhouette: the glass sheet AND the funnel that runs down into
// the clock, drawn as ONE closed outline.
//
// Why one shape rather than a sheet plus a separate tail item:
//
//   * Two translucent fills overlapping leave a visibly darker band exactly
//     where the two meet - the spec says the join must not be visible, and
//     @glassBg@ is translucent by design so the beam reads through it.
//   * A Rectangle cannot omit its border along part of one edge, so a
//     rectangular sheet always draws a line straight across the funnel's
//     mouth. Here the outline simply does not cross the mouth: it detours
//     down one flank, along the neck and back up the other.
//
// The path is a literal in 1080p-equivalent units and the whole Shape is
// scaled by uiScale. That is deliberate, not incidental: a ShapePath whose
// data comes from anything that changes draws NOTHING, silently (see
// docs/adding-a-bar-widget.md rule 4). Scaling the item keeps the data
// constant while the geometry still follows the output.
Item {
    id: root

    required property real uiScale

    // 0 hides the funnel, 1 extends it fully. The transitions in
    // ControlPanel.qml drive this; it is a clip, never a redrawn path.
    property real openFraction: 1

    // How much of the straight bottom edge to draw across the funnel's
    // mouth. 0 while docked - the outline detours down the flanks there, and
    // a line across the mouth is exactly what made the tail look like a
    // shape hung off a closed box. 1 once undocked, because then the funnel
    // is gone and without it the sheet has a 300px hole in its border.
    property real mouthClosed: 0

    readonly property color edgeColor: "@glassBorder@"

    readonly property real sheetWidth: 940
    readonly property real sheetHeight: 700
    readonly property real tailDrop: 34

    implicitWidth: sheetWidth * uiScale
    implicitHeight: (sheetHeight + tailDrop) * uiScale

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        transform: Scale {
            xScale: root.uiScale
            yScale: root.uiScale
        }

        ShapePath {
            fillColor: "@sheetBg@"
            strokeColor: "@glassBorder@"
            strokeWidth: 1

            // Clockwise from the top-left corner, round the sheet, then at
            // the bottom edge: right flank down, neck across, left flank up.
            // Mouth 320..620, neck 406..534 - the clock capsule is 128 wide
            // (ClockWidget implicitWidth), so the neck lands on it exactly.
            PathSvg {
                path: "M26 0 H914 A26 26 0 0 1 940 26 V674 A26 26 0 0 1 914 700 \
H620 C584 700 560 712 546 726 C542 730 540 734 534 734 \
H406 C400 734 398 730 394 726 C380 712 356 700 320 700 \
H26 A26 26 0 0 1 0 674 V26 A26 26 0 0 1 26 0 Z"
            }
        }

        // The mouth's own lid, faded in as the funnel retracts. A separate
        // ShapePath with its own literal, not a change to the one above:
        // path data that changes draws nothing at all (rule 4). Only the
        // stroke's alpha moves, which is a colour, not geometry.
        ShapePath {
            fillColor: "transparent"
            strokeWidth: 1
            strokeColor: Qt.rgba(root.edgeColor.r, root.edgeColor.g,
                                 root.edgeColor.b,
                                 root.edgeColor.a * root.mouthClosed)
            PathSvg { path: "M320 700 H620" }
        }
    }
}
