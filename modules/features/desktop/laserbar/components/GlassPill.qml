import QtQuick
import QtQuick.Effects

// Reusable "liquid glass" module template for the laser bar: a translucent
// pill (so the beam colors behind still read through, not fully hidden)
// wrapped in RevealMask so it reveals/covers in sync with the beam travel
// exactly like every other module. Meant to be the starting point for
// future modules, not just the clock.
//
// Usage:
//   GlassPill {
//       coverLeft: panel.leftExtent
//       coverRight: panel.rightExtent
//       panelWidth: panel.width
//       contentWidth: 220; contentHeight: 56
//       // children = your module's own content (Text, Row, Canvas, ...)
//   }
Item {
    id: root

    required property real coverLeft
    required property real coverRight
    required property real panelWidth
    required property real contentWidth
    required property real contentHeight

    width: contentWidth
    height: contentHeight

    default property alias content: inner.data

    RevealMask {
        id: mask
        anchors.fill: parent
        coverLeft: root.coverLeft
        coverRight: root.coverRight
        panelWidth: root.panelWidth
        // This RevealMask fills GlassPill exactly (no offset), but it's
        // still not a *direct* child of the panel - GlassPill (root) is.
        // RevealMask's own `x` is relative to its immediate parent (this
        // Item), which is always 0 here regardless of where GlassPill itself
        // sits, so it can't be used as the panel-relative origin on its own.
        originXOverride: root.x

        // The glass itself. Deliberately translucent (not a blurred capture
        // of what's behind - QtQuick has no cheap live backdrop-blur here)
        // so the beam colors passing underneath still show through faintly;
        // a soft top highlight sells the "liquid" sheen.
        Rectangle {
            id: glass
            anchors.fill: parent
            radius: height / 2
            color: "@glassBg@"
            border.color: "@glassBorder@"
            border.width: 1

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#26FFFFFF" }
                    GradientStop { position: 0.45; color: "#00FFFFFF" }
                }
            }
        }

        // Consumer content slot, centered above the glass.
        Item {
            id: inner
            anchors.centerIn: parent
            width: root.contentWidth
            height: root.contentHeight
        }
    }
}
