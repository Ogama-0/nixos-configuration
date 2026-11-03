import QtQuick

// A photo, full in the panel. `ControlPanel.pictureLayer` grows this out of
// the bubble that was tapped exactly the way `messagesLayer` grows
// `MessagesPane` out of the mobile zone (or a toast) - see that layer's own
// comment for the shape, which this component does not repeat any of.
//
// This file only draws what sits INSIDE that animated box: the picture
// itself, and a 44px foot strip that is the one piece of chrome a full-frame
// photo still needs - who sent it, when, and the way out.
Item {
    id: root

    property real uiScale: 1
    // A resolved URL - a data: URI for an inline image, a file:// one for a
    // fetched attachment - or "" when there is nothing to show at all. The
    // caller (ConversationView's attachment delegate) is the one place that
    // already knows which of those three this is; this component does not
    // re-derive it.
    property string source: ""
    property string who: ""
    property string when: ""
    // Set by the caller (`ControlPanel.openPicture`), not derived here -
    // true exactly when `source` turned out to be "" on arrival: an image
    // that is neither inline (the common case - see ConversationView's
    // `src` comment) nor backed by a fetch, because images arrive with
    // their bytes on the first announcement or not at all. Review Focus 5:
    // this state must say so, not hold an empty frame forever - see the
    // Text below.
    property bool missing: false

    readonly property real footH: 44 * root.uiScale

    // Fully opaque, same reasoning as `messagesBox.sheetGround` in
    // ControlPanel: this is a takeover of the whole stage, and a seam of
    // whatever sat underneath bleeding through at the edges would read as
    // a glitch rather than a photo arriving.
    Rectangle {
        anchors.fill: parent
        color: "@sheetBg@"
    }

    Item {
        id: frame
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: foot.top

        Image {
            anchors.fill: parent
            anchors.margins: 8 * root.uiScale
            visible: !root.missing
            source: root.missing ? "" : root.source
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        // Not an empty frame. A picture can fail to arrive at all - see
        // `missing` above - and the honest answer belongs where the photo
        // would have been, not buried in the foot strip next to the
        // timestamp.
        Text {
            visible: root.missing
            anchors.centerIn: parent
            width: parent.width * 0.6
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Your phone did not send this picture."
            color: "@mutedColor@"
            font.pixelSize: Math.round(13 * root.uiScale)
        }
    }

    Rectangle {
        id: foot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.footH
        color: "@plateBg@"

        Rectangle {
            width: parent.width
            height: 1
            color: "@glassBorder@"
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16 * root.uiScale
            anchors.verticalCenter: parent.verticalCenter
            text: root.who + " · " + root.when
            color: "@mutedColor@"
            font.pixelSize: Math.round(12 * root.uiScale)
            elide: Text.ElideRight
            width: parent.width * 0.6
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 16 * root.uiScale
            anchors.verticalCenter: parent.verticalCenter
            text: "Esc to close"
            // Lower alpha than the label on the left: it is a standing
            // hint, not news, and should not compete with who/when for the
            // eye on first glance.
            color: Qt.rgba(mutedTok.r, mutedTok.g, mutedTok.b, 0.55)
            readonly property color mutedTok: "@mutedColor@"
            font.pixelSize: Math.round(11 * root.uiScale)
        }
    }
}
