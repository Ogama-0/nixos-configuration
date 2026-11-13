import QtQuick

// A person, in a circle, with no photo to put in it.
//
// KDE Connect syncs 229 contact cards and not one carries a PHOTO field, so
// identity here is two letters and a colour - see MessageHue for why the
// colour is hashed and never assigned by position.
//
// A dumb view. It resolves nothing and looks nothing up: initials, hue and
// label are handed to it. That is deliberate - this sits inside ListView
// delegates, and a component that reached for a model would have to have one
// threaded down to it through every container on the way.
//
// Four states, and the vocabulary is the panel's own rather than a chat
// app's. The disc is the faint resting plate a ToggleTile sits on; the ring
// is the accent edge a notification group wears; the filled state is the
// accent fill with on-accent ink that a tile already uses when it is on.
Item {
    id: root

    property real uiScale: 1
    property real size: 62
    // Empty for a shortcode or an unsaved number: there is no name to take
    // initials from, so the label is drawn instead.
    property string initials: ""
    property string label: ""
    property color hue: "@mutedColor@"
    property bool unread: false
    property bool open: false

    // A group conversation stacks a second disc behind the first.
    property string secondInitials: ""
    property color secondHue: "@mutedColor@"
    // Stacked only when there is room to read both. At the 34px a list row
    // gives it, two discs and four letters collapse into a smudge that says
    // less than one clear initial pair does - so below the threshold a group
    // is drawn as a single avatar and the row's name carries the rest.
    readonly property bool isGroup: secondInitials.length > 0
                                    && size * uiScale >= 48

    implicitWidth: size * uiScale
    implicitHeight: size * uiScale
    width: implicitWidth
    height: implicitHeight

    // ---- group: the one behind ----

    Rectangle {
        visible: root.isGroup
        width: parent.width * 0.62
        height: width
        radius: width / 2
        x: 0
        y: 0
        color: "@plateBg@"
        border.width: 2 * root.uiScale
        border.color: Qt.rgba(root.secondHue.r, root.secondHue.g,
                              root.secondHue.b, 0.34)

        Text {
            anchors.centerIn: parent
            text: root.secondInitials
            color: root.secondHue
            font.pixelSize: Math.round(parent.width * 0.30)
            font.weight: Font.DemiBold
        }
    }

    // ---- the disc ----

    Rectangle {
        id: disc
        width: root.isGroup ? parent.width * 0.70 : parent.width
        height: width
        radius: width / 2
        x: parent.width - width
        y: parent.height - height

        // Filled when this is the thread you are reading, faint plate
        // otherwise. The fill is the whole signal, which is why the ring
        // disappears underneath it rather than doubling up.
        color: root.open ? root.hue : "@plateBg@"

        border.width: root.open ? 0 : Math.round(2 * root.uiScale)
        border.color: root.unread
            ? root.hue
            : Qt.rgba(root.hue.r, root.hue.g, root.hue.b, 0.34)

        Behavior on color { ColorAnimation { duration: 120 } }

        // The front disc of a group is cut out of the ground so the one
        // behind reads as behind, not as a crescent stuck to its side.
        Rectangle {
            visible: root.isGroup
            anchors.centerIn: parent
            width: parent.width + 5 * root.uiScale
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2.5 * root.uiScale
            border.color: "@sheetBg@"
            z: -1
        }

        // Initials, or - with no card to take them from - the number itself.
        // Not an empty circle: a shortcode is still recognisable as 32665,
        // and an avatar with nothing in it reads as a failure to load.
        Text {
            anchors.centerIn: parent
            width: parent.width - 8 * root.uiScale
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.initials !== "" ? root.initials : root.label
            color: root.open ? "@msgAccentInk@" : root.hue
            font.pixelSize: root.initials !== ""
                ? Math.round(parent.width * 0.34)
                : Math.round(parent.width * 0.22)
            font.weight: Font.DemiBold
        }
    }

    // ---- the sweep ----
    //
    // The bar reveals its capsules with a travelling edge; this is that edge
    // closed into a circle, run once when a message lands. Once, not looped:
    // six pinned avatars quietly pulsing would be a light show, and the
    // unread state is already carried by the ring sitting at full strength
    // afterwards.
    //
    // Behind a Loader so it does not exist at all when it is not running. A
    // Canvas per conversation row, idle, repainting on every size change, is
    // the kind of thing docs/adding-a-bar-widget.md exists to warn about.
    Loader {
        id: sweep
        anchors.fill: disc
        anchors.margins: 0
        x: disc.x
        y: disc.y
        active: false
        asynchronous: false
        sourceComponent: sweepArc
    }

    onUnreadChanged: if (unread && !open) sweep.active = true

    Component {
        id: sweepArc
        Canvas {
            id: arc
            property real progress: 0
            onProgressChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const w = Math.round(2 * root.uiScale);
                const r = (width - w) / 2;
                ctx.lineWidth = w;
                ctx.strokeStyle = root.hue;
                ctx.lineCap = "round";
                ctx.beginPath();
                // From twelve o'clock, clockwise.
                ctx.arc(width / 2, height / 2, r,
                        -Math.PI / 2,
                        -Math.PI / 2 + 2 * Math.PI * arc.progress);
                ctx.stroke();
            }

            NumberAnimation on progress {
                from: 0; to: 1
                duration: 420
                easing.type: Easing.OutCubic
                running: true
                // Unloads itself. The ring underneath is already at full
                // strength by now, so there is nothing to hand over.
                onFinished: sweep.active = false
            }
        }
    }
}
