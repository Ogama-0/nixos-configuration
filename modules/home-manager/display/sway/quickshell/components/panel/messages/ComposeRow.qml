import QtQuick
import Quickshell
import Quickshell.Io
import "../" as Panel

// Where you type. The reason the whole pane has to hold keyboard focus.
//
// Enter sends, Shift+Enter breaks the line. The field grows with the text to
// a ceiling and then scrolls, because a four-line message should not push the
// conversation off the top of the pane.
//
// Disabled rather than hidden when the phone is away: a compose box that
// vanishes looks like a panel that is broken, and one that silently eats
// what you type is worse than both.
Item {
    id: root

    property real uiScale: 1
    property bool enabled: true
    property string placeholder: "Text message"
    property string disabledText: "Phone not reachable"
    property alias draft: field.text

    // Paths staged by the picker or a paste, sent with the next message.
    property var attachments: []

    signal sendRequested(string text, var attachments)

    readonly property int maxHeight: 92

    implicitHeight: Math.max(56, field.implicitHeight + 26) * uiScale
    height: implicitHeight

    function focusField(): void { field.forceActiveFocus(); }
    function clear(): void { field.text = ""; root.attachments = []; }

    function submit(): void {
        if (!root.enabled) return;
        if (!field.text.trim() && root.attachments.length === 0) return;
        root.sendRequested(field.text, root.attachments);
        root.clear();
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"

        Rectangle {
            width: parent.width
            height: 1
            color: "@glassBorder@"
        }
    }

    // Staged attachments, above the field, each removable. Without this a
    // picked file is invisible until it has already been sent.
    Row {
        id: staged
        visible: root.attachments.length > 0
        x: 54 * root.uiScale
        y: 6 * root.uiScale
        spacing: 6 * root.uiScale

        Repeater {
            model: root.attachments
            delegate: Rectangle {
                required property string modelData
                required property int index
                height: 20 * root.uiScale
                width: chip.implicitWidth + 24 * root.uiScale
                radius: height / 2
                color: "@plateBg@"

                Text {
                    id: chip
                    x: 9 * root.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(parent.modelData).split("/").pop()
                    color: "@mutedColor@"
                    font.pixelSize: Math.round(10.5 * root.uiScale)
                    elide: Text.ElideMiddle
                }

                Text {
                    x: parent.width - 13 * root.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    text: "×"
                    color: "@mutedColor@"
                    font.pixelSize: Math.round(12 * root.uiScale)

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6 * root.uiScale
                        onClicked: {
                            let a = root.attachments.slice();
                            a.splice(parent.parent.index, 1);
                            root.attachments = a;
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: plus
        x: 16 * root.uiScale
        y: parent.height - height - 13 * root.uiScale
        width: 30 * root.uiScale
        height: 30 * root.uiScale
        radius: width / 2
        color: plusArea.containsMouse && root.enabled ? "@glassBorder@" : "@plateBg@"
        opacity: root.enabled ? 1 : 0.4

        Text {
            anchors.centerIn: parent
            text: "+"
            color: "@mutedColor@"
            font.pixelSize: Math.round(17 * root.uiScale)
        }

        MouseArea {
            id: plusArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.enabled
            onClicked: picker.running = true
        }
    }

    Rectangle {
        id: fieldBox
        x: plus.x + plus.width + 10 * root.uiScale
        y: 10 * root.uiScale + (staged.visible ? 20 * root.uiScale : 0)
        width: parent.width - x - 58 * root.uiScale
        height: parent.height - y - 13 * root.uiScale
        radius: 16 * root.uiScale
        color: "transparent"
        border.width: 1
        border.color: field.activeFocus ? "@msgAccent@" : "@glassBorder@"
        opacity: root.enabled ? 1 : 0.5

        Flickable {
            anchors.fill: parent
            anchors.leftMargin: 14 * root.uiScale
            anchors.rightMargin: 10 * root.uiScale
            anchors.topMargin: 7 * root.uiScale
            anchors.bottomMargin: 7 * root.uiScale
            contentHeight: field.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            TextEdit {
                id: field
                width: parent.width
                color: "@clockColor@"
                font.pixelSize: Math.round(13 * root.uiScale)
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                enabled: root.enabled
                // The pane's own Escape handler needs the key; a TextEdit
                // would otherwise swallow it along with everything else.
                Keys.onEscapePressed: event => event.accepted = false

                Keys.onReturnPressed: event => {
                    if (event.modifiers & Qt.ShiftModifier) {
                        event.accepted = false;   // a newline, as asked
                        return;
                    }
                    event.accepted = true;
                    root.submit();
                }

                // Paste an image and it becomes an attachment rather than a
                // line of binary in the message body. wl-paste decides
                // whether there is an image on the clipboard at all - asking
                // it is cheaper than tracking clipboard ownership ourselves.
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                        pasteProbe.running = true;
                        // Not accepted: a clipboard holding text should still
                        // paste as text, and the probe is what decides.
                    }
                }

                Text {
                    visible: field.text.length === 0
                    text: root.enabled ? root.placeholder : root.disabledText
                    color: "@mutedColor@"
                    font: field.font
                }
            }
        }
    }

    Rectangle {
        id: sendButton
        x: parent.width - width - 16 * root.uiScale
        y: parent.height - height - 13 * root.uiScale
        width: 30 * root.uiScale
        height: 30 * root.uiScale
        radius: width / 2
        color: "@msgAccent@"
        opacity: (root.enabled && (field.text.trim() || root.attachments.length > 0))
                 ? 1 : 0.35

        Text {
            anchors.centerIn: parent
            text: "↑"
            color: "@msgAccentInk@"
            font.pixelSize: Math.round(14 * root.uiScale)
            font.weight: Font.DemiBold
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.enabled
            onClicked: root.submit()
        }
    }

    // Picker then stage. One shell because a cancelled picker must stage
    // nothing: zenity exits non-zero, && stops, and the echo never runs.
    // Same shape as MobileModel.sendFile, for the same reason.
    Process {
        id: picker
        command: ["sh", "-c", "zenity --file-selection --title='Attach to message'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = this.text.trim();
                if (path) root.attachments = root.attachments.concat([path]);
            }
        }
    }

    // Writes the clipboard image to a temp file and stages it, or does
    // nothing at all when the clipboard holds no image.
    Process {
        id: pasteProbe
        command: ["sh", "-c",
            "wl-paste --list-types 2>/dev/null | grep -q '^image/' || exit 1; "
            + "f=$(mktemp --suffix=.png /tmp/qs-paste-XXXXXX); "
            + "wl-paste --type image/png > \"$f\" && printf '%s' \"$f\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = this.text.trim();
                if (path) root.attachments = root.attachments.concat([path]);
            }
        }
    }
}
