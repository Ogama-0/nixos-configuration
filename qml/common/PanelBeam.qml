import QtQuick

// A zone divider: a hairline that fades out at both ends, so the panel reads
// as one sheet ruled into regions rather than a tray of cards.
//
// It is the beam's own colour, not a neutral grey, because that is the point:
// the panel comes out of the laser and the laser is what divides it. Carried
// at low alpha - a full-strength rule every 300px would compete with the
// content it is separating.
Rectangle {
    id: root

    property bool horizontal: false
    property real uiScale: 1

    // @greenColor@ is opaque; the divider wants the same hue at a fraction of
    // it, and there is no translucent-accent token to reach for.
    readonly property color beamColor: {
        const c = Qt.color("@greenColor@");
        return Qt.rgba(c.r, c.g, c.b, 0.30);
    }

    implicitWidth: horizontal ? parent.width : 1
    implicitHeight: horizontal ? 1 : parent.height

    gradient: Gradient {
        orientation: root.horizontal ? Gradient.Horizontal : Gradient.Vertical
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.14; color: root.beamColor }
        GradientStop { position: 0.86; color: root.beamColor }
        GradientStop { position: 1.0; color: "transparent" }
    }
}
