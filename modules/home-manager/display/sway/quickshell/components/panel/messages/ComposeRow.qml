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
    // Back out of the field without leaving the pane. The sidebar is the
    // only other keyboard stop, so there is nowhere else this can mean.
    signal backFocusAsked()
    signal searchFocusAsked()

    // The chrome around the text, named rather than summed into a constant,
    // because the constant was WRONG and that is the entire bug: the row
    // reserved `field.implicitHeight + 26` while the box below it actually
    // takes 10 above, 13 below and 7+7 inside the Flickable - 37. The visible
    // area was eleven pixels, most of a line, short of the content. One line
    // fitted only because the 56px floor covered the gap; the second was
    // hidden behind the conversation above, and the box looked like it only
    // started growing at the third line.
    readonly property real fieldTopGap: 10
    readonly property real fieldBottomGap: 13
    readonly property real fieldInnerPad: 7
    // A staged attachment pushes the field down by this much, and it has to be
    // reserved too or it eats the same line over again.
    readonly property real stagedGap: staged.visible ? 20 : 0
    readonly property real chrome: fieldTopGap + fieldBottomGap
                                   + 2 * fieldInnerPad + stagedGap

    // One line of this font, measured rather than assumed.
    readonly property real lineHeight: field.lineCount > 0
        ? field.implicitHeight / field.lineCount
        : field.font.pixelSize * 1.45

    // Three lines, then it scrolls - what the header above has always claimed
    // and nothing implemented: `maxHeight` was declared and never read, so a
    // long message grew the box until it pushed the conversation off the top
    // of the pane. Counted in LINES, not pixels: a pixel ceiling cuts the last
    // line in half, which is the artifact this whole block is about.
    readonly property int maxLines: 3
    readonly property real maxHeight: root.lineHeight * root.maxLines
                                      + root.chrome * root.uiScale

    // The text, and how much of it can be seen. Read by
    // tests/laserbar/messages-compose-size.qml; nothing uses them at runtime.
    readonly property real textHeight: field.implicitHeight
    readonly property real visibleTextHeight: flick.height

    // uiScale multiplies the CHROME only. field.implicitHeight is already in
    // scaled pixels because the font size is, so the old
    // `(field.implicitHeight + 26) * uiScale` scaled the text twice.
    implicitHeight: Math.min(root.maxHeight,
                             Math.max(56 * uiScale,
                                      field.implicitHeight + chrome * uiScale))
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
        y: (root.fieldTopGap + root.stagedGap) * root.uiScale
        width: parent.width - x - 58 * root.uiScale
        height: parent.height - y - root.fieldBottomGap * root.uiScale
        radius: 16 * root.uiScale
        color: "transparent"
        border.width: 1
        border.color: field.activeFocus ? "@msgAccent@" : "@glassBorder@"
        opacity: root.enabled ? 1 : 0.5

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.leftMargin: 14 * root.uiScale
            anchors.rightMargin: 10 * root.uiScale
            anchors.topMargin: root.fieldInnerPad * root.uiScale
            anchors.bottomMargin: root.fieldInnerPad * root.uiScale
            contentHeight: field.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // Past the ceiling the box stops growing, so typing has to follow
            // the cursor - a Flickable does not do that for a TextEdit inside
            // it, and without it the fourth line is typed into a region you
            // cannot see.
            function followCursor(): void {
                const r = field.cursorRectangle;
                if (r.y < flick.contentY) flick.contentY = r.y;
                else if (r.y + r.height > flick.contentY + flick.height)
                    flick.contentY = r.y + r.height - flick.height;
            }

            TextEdit {
                id: field
                width: parent.width
                color: "@clockColor@"
                font.pixelSize: Math.round(13 * root.uiScale)
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                enabled: root.enabled
                onCursorRectangleChanged: flick.followCursor()
                // Deleting back down to one line leaves contentY past the
                // end, which reads as a blank field with the text above it.
                onImplicitHeightChanged: flick.returnToBounds()
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

                // Shift+Tab is back to the conversation list; Tab carries on
                // round to the search box. Two stops and a field, so the
                // cycle is short enough to be worth closing.
                Keys.onBacktabPressed: event => {
                    event.accepted = true;
                    root.backFocusAsked();
                }
                Keys.onTabPressed: event => {
                    event.accepted = true;
                    root.searchFocusAsked();
                }
                // Left arrow, but ONLY on an empty field: in a draft the
                // left arrow is the cursor, and stealing it would make the
                // compose box unusable for the sake of a shortcut.
                Keys.onLeftPressed: event => {
                    if (field.text.length > 0 || field.cursorPosition > 0) {
                        event.accepted = false;
                        return;
                    }
                    event.accepted = true;
                    root.backFocusAsked();
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
