import QtQuick
import Quickshell.Io

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
    // Derived, not settable: "" is the one value `source` takes when an
    // image was neither inline (the common case - see ConversationView's
    // `src` comment) nor backed by a fetch, because images arrive with
    // their bytes on the first announcement or not at all. A separate
    // settable property here was redundant with `source` by construction -
    // `ControlPanel.openPicture` computed it as `source === ""` and handed
    // both over - which left a desync open that could never actually
    // happen (there is no path that sets one without the other), so there
    // was no real state here for the fixture's "missing-corner" probe to
    // exercise either. This state still has to say so, not hold an empty
    // frame forever - see the Text below.
    readonly property bool missing: root.source === ""

    readonly property real footH: 44 * root.uiScale

    // There is no second, lower-quality copy of an image anywhere in this
    // pipeline - docs/kdeconnect-sms-payload.md has no thumbnail field, and
    // ConversationView's `src` is either the SAME base64EncodedFile this
    // Image decodes, or the same fetched file path. `source` already IS the
    // full-quality original; this file only has to put it on screen at full
    // size (PreserveAspectFit, below) rather than reuse the small bubble's
    // own cached layer - which it already did not do.

    // Returns whether anything was actually put on the clipboard, so the
    // button can only claim "Copied" when it was. It used to be void and the
    // caller set `copied` unconditionally - every source that is neither a
    // data: URI nor a file:// path (an empty one, most of all) fell out of
    // the bottom having done nothing, and said it had copied.
    function copyToClipboard(): bool {
        if (root.missing) return false;
        if (root.source.indexOf("data:") === 0) {
            const comma = root.source.indexOf(",");
            const header = root.source.slice(5, comma); // "<mime>;base64"
            const mime = header.split(";")[0];
            // $1 rather than interpolating mime into the script string - the
            // mime comes off the wire (the attachment's own announced type)
            // and a positional arg is immune to it containing anything a
            // shell would treat as special.
            copyProc.command = ["sh", "-c", 'base64 -d | wl-copy --type "$1"',
                                "sh", mime];
            copyProc.stdinEnabled = true;
            copyProc.running = true;
            copyProc.write(root.source.slice(comma + 1));
            // Closes the pipe so `base64 -d` sees EOF and wl-copy gets a
            // complete image instead of hanging on a stdin nobody closed.
            copyProc.stdinEnabled = false;
            return true;
        } else if (root.source.indexOf("file://") === 0) {
            // kdeconnect's cache paths carry a literal "%" (see
            // ConversationView's `src`), and decodeURI throws URIError on a
            // "%" that does not begin a valid escape - which would abort
            // this handler on the way past. The raw path is the better
            // answer than no copy at all.
            let path = root.source.slice(7);
            try { path = decodeURI(path); } catch (e) { }
            const ext = path.slice(path.lastIndexOf(".") + 1).toLowerCase();
            const mime = ext === "png" ? "image/png"
                : ext === "gif" ? "image/gif"
                : ext === "webp" ? "image/webp" : "image/jpeg";
            // Same reasoning as above, now for a filesystem path - it is the
            // phone's own filename, not something to trust inside a string.
            copyProc.command = ["sh", "-c", 'wl-copy --type "$1" < "$2"',
                                "sh", mime, path];
            copyProc.stdinEnabled = false;
            copyProc.running = true;
            return true;
        }
        return false;
    }

    Process { id: copyProc }

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

        Rectangle {
            visible: !root.missing
            anchors.right: parent.right
            anchors.rightMargin: 96 * root.uiScale
            anchors.verticalCenter: parent.verticalCenter
            width: copyLabel.implicitWidth + 20 * root.uiScale
            height: 26 * root.uiScale
            radius: height / 2
            color: copyArea.containsMouse ? "@glassBorder@" : "@plateBg@"

            Text {
                id: copyLabel
                anchors.centerIn: parent
                text: root.copied ? "Copied" : "Copy"
                color: "@clockColor@"
                font.pixelSize: Math.round(11.5 * root.uiScale)
            }

            MouseArea {
                id: copyArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!root.copyToClipboard()) return;
                    root.copied = true;
                    copiedReset.restart();
                }
            }
        }
    }

    // Flips the button's own label back after a moment - the only
    // confirmation a clipboard write gets, since there is nothing else to
    // show for it.
    property bool copied: false
    Timer {
        id: copiedReset
        interval: 1500
        repeat: false
        onTriggered: root.copied = false
    }
}
