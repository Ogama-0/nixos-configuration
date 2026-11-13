import QtQuick

// A text, the moment it lands, with somewhere to answer it.
//
// This is the thing the whole feature was asked for: "I wanted to be able to
// click on a notification to answer easily." So the reply field is here, not
// behind a panel - typing in it and pressing Enter sends, and the panel
// never opens.
//
// Double-clicking anywhere else opens Messages on this thread instead, for
// when the answer needs more than one line or you want to read back.
//
// The field does NOT take focus when the toast appears. A text arriving
// mid-sentence that quietly started eating your keystrokes would be far
// worse than one more click.
Item {
    id: root

    property real uiScale: 1
    property string title: ""
    property string initials: ""
    property string preview: ""
    property color hue: "@mutedColor@"
    property string convId: ""
    property bool replying: false
    property bool sent: false

    signal replySent(string text)
    signal paneAsked()
    signal dismissed()

    implicitWidth: 380 * uiScale
    implicitHeight: body.implicitHeight + 26 * uiScale
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: 16 * root.uiScale
        color: "@sheetBg@"
        border.width: 1
        border.color: "@glassBorder@"
    }

    MessageAvatar {
        id: avatar
        x: 15 * root.uiScale
        y: 13 * root.uiScale
        size: 38
        uiScale: root.uiScale
        initials: root.initials
        label: root.title
        hue: root.hue
    }

    Column {
        id: body
        x: avatar.x + avatar.width + 11 * root.uiScale
        y: 13 * root.uiScale
        width: parent.width - x - 15 * root.uiScale
        spacing: 2 * root.uiScale

        Text {
            width: parent.width
            text: root.title
            color: "@clockColor@"
            font.pixelSize: Math.round(13 * root.uiScale)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: root.preview
            color: "@mutedColor@"
            font.pixelSize: Math.round(12.5 * root.uiScale)
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Item { width: 1; height: 8 * root.uiScale }

        // Collapses to a confirmation once sent, rather than clearing itself
        // and sitting there looking like it did nothing.
        Text {
            visible: root.sent
            text: "Sent"
            color: "@msgAccent@"
            font.pixelSize: Math.round(11.5 * root.uiScale)
        }

        Rectangle {
            visible: !root.sent
            width: parent.width
            height: 30 * root.uiScale
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: replyField.activeFocus ? "@msgAccent@" : "@glassBorder@"

            TextInput {
                id: replyField
                x: 13 * root.uiScale
                width: parent.width - x - 36 * root.uiScale
                anchors.verticalCenter: parent.verticalCenter
                color: "@clockColor@"
                font.pixelSize: Math.round(12 * root.uiScale)
                clip: true

                onActiveFocusChanged: root.replying = activeFocus

                onAccepted: {
                    if (!text.trim()) return;
                    root.replySent(text);
                    root.sent = true;
                }

                // Leaves the toast without dismissing the panel behind it.
                Keys.onEscapePressed: event => {
                    event.accepted = true;
                    root.focus = false;
                    root.dismissed();
                }

                Text {
                    visible: replyField.text.length === 0
                    text: "Reply"
                    color: "@mutedColor@"
                    font: replyField.font
                }
            }

            Rectangle {
                x: parent.width - width - 4 * root.uiScale
                anchors.verticalCenter: parent.verticalCenter
                width: 22 * root.uiScale
                height: 22 * root.uiScale
                radius: width / 2
                color: "@msgAccent@"
                opacity: replyField.text.trim() ? 1 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: "↑"
                    color: "@msgAccentInk@"
                    font.pixelSize: Math.round(11 * root.uiScale)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!replyField.text.trim()) return;
                        root.replySent(replyField.text);
                        root.sent = true;
                    }
                }
            }
        }
    }

    // Everything that is not the reply field. Double-click opens the pane;
    // a single click is left alone so clicking near the toast to focus it
    // does not fling a panel open.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        // Below the reply row, so typing in it still works.
        z: -1
        onDoubleClicked: root.paneAsked()
    }
}
