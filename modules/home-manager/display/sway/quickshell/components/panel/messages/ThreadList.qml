import QtQuick
import "../" as Panel

// The sidebar: who has written to you, and who you care about most.
//
// Two halves, and the split is the point. The pinned grid is recognition -
// six faces you reach for without reading - so it is avatars with names
// under them and nothing else. The list below is triage: name, two lines of
// what they said, when. You scan the grid; you read the list.
//
// Pinning is the panel's own idea. KDE Connect has no notion of a pinned
// thread, so it lives in MessageStore and arrives here as a flag on the
// conversation.
//
// A view. It holds no model, fetches nothing, and persists nothing: it is
// handed a list and raises signals when the user does something to it.
Item {
    id: root

    property real uiScale: 1
    property var conversations: []
    property string activeId: ""
    // Set by the owner when a search has run and found nothing in the cache,
    // so the empty line can say which kind of nothing it is.
    property bool searchedBodies: true

    signal conversationPicked(string convId)
    signal pinToggled(string convId)
    signal composeAsked()

    property string query: ""

    readonly property var pinned: root.conversations.filter(c => c.pinned === true)

    // Newest first. Pinned threads stay in the list as well as the grid:
    // promoting them out of it would mean a message from a pinned contact
    // arrived somewhere you were not looking.
    readonly property var listed: {
        const q = root.query.trim().toLowerCase();
        const all = root.conversations.slice();
        all.sort((a, b) => (b.ts || 0) - (a.ts || 0));
        if (!q) return all;
        return all.filter(c =>
            String(c.title || "").toLowerCase().indexOf(q) >= 0
            || String(c.number || "").toLowerCase().indexOf(q) >= 0
            || String(c.preview || "").toLowerCase().indexOf(q) >= 0);
    }

    function relativeTime(ts: real): string {
        if (!ts) return "";
        const d = new Date(ts);
        const now = new Date();
        const sameDay = d.toDateString() === now.toDateString();
        if (sameDay) return Qt.formatTime(d, "HH:mm");
        const yesterday = new Date(now.getTime() - 86400000);
        if (d.toDateString() === yesterday.toDateString()) return "Hier";
        if (now.getTime() - ts < 7 * 86400000) return Qt.formatDate(d, "ddd");
        return Qt.formatDate(d, "dd/MM");
    }

    // ---- search and compose ----

    Item {
        id: head
        x: 14 * root.uiScale
        y: 14 * root.uiScale
        width: parent.width - 28 * root.uiScale
        height: 32 * root.uiScale

        Rectangle {
            id: searchBox
            width: parent.width - 42 * root.uiScale
            height: parent.height
            radius: height / 2
            color: "@plateBg@"

            Panel.PanelIcon {
                id: searchIcon
                name: "search"
                anchors.verticalCenter: parent.verticalCenter
                x: 11 * root.uiScale
                uiScale: root.uiScale * 0.55
                color: "@mutedColor@"
            }

            TextInput {
                id: queryField
                anchors.verticalCenter: parent.verticalCenter
                x: searchIcon.x + searchIcon.width + 8 * root.uiScale
                width: parent.width - x - 10 * root.uiScale
                color: "@clockColor@"
                font.pixelSize: Math.round(13 * root.uiScale)
                clip: true
                onTextChanged: root.query = text

                Text {
                    visible: queryField.text.length === 0
                    text: "Search"
                    color: "@mutedColor@"
                    font: queryField.font
                }
            }
        }

        Rectangle {
            x: parent.width - 32 * root.uiScale
            width: 32 * root.uiScale
            height: parent.height
            radius: 9 * root.uiScale
            color: composeArea.containsMouse ? "@plateBg@" : "transparent"
            border.width: 1
            border.color: "@glassBorder@"

            Panel.PanelIcon {
                anchors.centerIn: parent
                name: "edit"
                uiScale: root.uiScale * 0.55
                color: composeArea.containsMouse ? "@msgAccent@" : "@mutedColor@"
            }

            MouseArea {
                id: composeArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.composeAsked()
            }
        }
    }

    // ---- the pinned grid ----
    //
    // Three wide, and it scrolls rather than growing a third row. The list
    // underneath is the thing you came for; a grid that pushed it off the
    // bottom as you pinned a seventh person would punish you for using the
    // feature.

    Flickable {
        id: pinArea
        x: 0
        y: head.y + head.height + 10 * root.uiScale
        width: parent.width
        height: Math.min(pinGrid.implicitHeight, 2 * 92 * root.uiScale)
        contentHeight: pinGrid.implicitHeight
        clip: true
        visible: root.pinned.length > 0
        boundsBehavior: Flickable.StopAtBounds

        Grid {
            id: pinGrid
            columns: 3
            width: parent.width
            leftPadding: 14 * root.uiScale
            rightPadding: 14 * root.uiScale
            rowSpacing: 14 * root.uiScale

            Repeater {
                model: root.pinned
                delegate: Item {
                    required property var modelData
                    width: (pinGrid.width - 28 * root.uiScale) / 3
                    height: 88 * root.uiScale

                    MessageAvatar {
                        id: pinAvatar
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: 62
                        uiScale: root.uiScale
                        initials: parent.modelData.initials || ""
                        label: parent.modelData.title || ""
                        hue: parent.modelData.hue
                        unread: parent.modelData.unread === true
                        open: parent.modelData.convId === root.activeId
                        secondInitials: parent.modelData.isGroup
                            ? (parent.modelData.secondInitials || "") : ""
                        secondHue: parent.modelData.secondHue || parent.modelData.hue
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: pinAvatar.bottom
                        anchors.topMargin: 6 * root.uiScale
                        width: parent.width - 6 * root.uiScale
                        horizontalAlignment: Text.AlignHCenter
                        text: parent.modelData.title || ""
                        color: "@mutedColor@"
                        font.pixelSize: Math.round(11 * root.uiScale)
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                root.pinToggled(parent.modelData.convId);
                            else
                                root.conversationPicked(parent.modelData.convId);
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: divider
        x: 0
        y: pinArea.visible ? pinArea.y + pinArea.height + 8 * root.uiScale
                           : head.y + head.height + 12 * root.uiScale
        width: parent.width
        height: 1
        color: "@glassBorder@"
    }

    // ---- the conversations ----

    ListView {
        id: list
        x: 0
        y: divider.y + 1
        width: parent.width
        height: parent.height - y
        clip: true
        model: root.listed
        // Not a delegate per conversation: the whole point of a ListView here
        // is that a hundred threads cost the dozen rows you can see.
        cacheBuffer: 200 * root.uiScale
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: row
            required property var modelData
            width: list.width
            height: 56 * root.uiScale

            readonly property bool selected: modelData.convId === root.activeId

            Rectangle {
                anchors.fill: parent
                anchors.rightMargin: 8 * root.uiScale
                radius: 10 * root.uiScale
                // @glassBg@ is a 40%-BLACK wash and is invisible on a sheet
                // that is already near-black - the selected row looked
                // identical to its neighbours. @glassBorder@ is the light
                // one, and reads as a raised plate in both variants.
                color: row.selected ? "@glassBorder@"
                     : rowArea.containsMouse ? "@plateBg@" : "transparent"
            }

            // The same 2px accent edge a notification group wears, for the
            // same reason: it marks the row without taking any width from
            // what the row is trying to say.
            Rectangle {
                visible: row.modelData.unread === true
                x: 0
                y: 8 * root.uiScale
                width: 2 * root.uiScale
                height: parent.height - 16 * root.uiScale
                radius: width
                color: row.modelData.hue
            }

            MessageAvatar {
                id: rowAvatar
                x: 14 * root.uiScale
                anchors.verticalCenter: parent.verticalCenter
                size: 34
                uiScale: root.uiScale
                initials: row.modelData.initials || ""
                label: row.modelData.title || ""
                hue: row.modelData.hue
                unread: row.modelData.unread === true
                open: row.selected
                secondInitials: row.modelData.isGroup
                    ? (row.modelData.secondInitials || "") : ""
                secondHue: row.modelData.secondHue || row.modelData.hue
            }

            Text {
                id: when
                anchors.right: parent.right
                anchors.rightMargin: 16 * root.uiScale
                y: 9 * root.uiScale
                text: root.relativeTime(row.modelData.ts)
                color: "@mutedColor@"
                font.pixelSize: Math.round(10.5 * root.uiScale)
            }

            Text {
                id: who
                x: rowAvatar.x + rowAvatar.width + 10 * root.uiScale
                y: 8 * root.uiScale
                width: when.x - x - 8 * root.uiScale
                text: row.modelData.title || ""
                color: "@clockColor@"
                font.pixelSize: Math.round(13 * root.uiScale)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                x: who.x
                y: who.y + who.height + 1 * root.uiScale
                width: parent.width - x - 16 * root.uiScale
                height: 28 * root.uiScale
                text: row.modelData.preview || ""
                color: "@mutedColor@"
                font.pixelSize: Math.round(12 * root.uiScale)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        root.pinToggled(row.modelData.convId);
                    else
                        root.conversationPicked(row.modelData.convId);
                }
            }
        }
    }

    // Empty is a sentence, not a blank. And it has to say WHICH nothing this
    // is: the cache only holds conversations you have opened, so "no match"
    // and "no match in what has been downloaded" are different answers and
    // only one of them means give up.
    Text {
        visible: root.listed.length === 0
        x: 20 * root.uiScale
        y: list.y + 20 * root.uiScale
        width: parent.width - 40 * root.uiScale
        wrapMode: Text.WordWrap
        color: "@mutedColor@"
        font.pixelSize: Math.round(12.5 * root.uiScale)
        text: root.query.length === 0
            ? "No conversations yet."
            : root.searchedBodies
                ? "Nothing matches “" + root.query + "”."
                : "Nothing matches “" + root.query + "” in the conversations "
                  + "you have opened. Older threads are still on the phone."
    }
}
