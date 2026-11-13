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
//
// A FocusScope rather than an Item: the search field and the conversation
// list are both keyboard stops, and arrowing between them has to work
// without the pane above having to know which one is live.
FocusScope {
    id: root

    property real uiScale: 1
    property var conversations: []
    property string activeId: ""
    // The pane binds this to MessagesPane.arrowsBorrowed(...) - the single
    // source of truth for the decision - so the Right/Left handlers below
    // only ever read it, never recompute it. Defaults to false so a fixture
    // that never sets it (no audio, no pane) behaves as if nothing is
    // playing.
    property bool arrowsBorrowed: false
    // Set by the owner when a search has run and found nothing in the cache,
    // so the empty line can say which kind of nothing it is.
    property bool searchedBodies: true

    // Conversation ids whose cached message BODIES match the query. The
    // owner computes these - a view does not get to hold a database - and
    // they are unioned with the name/number/preview match below.
    property var bodyMatches: []

    signal conversationPicked(string convId)
    signal pinToggled(string convId)
    signal removeAsked(string convId)
    signal blockAsked(string convId)
    signal composeAsked()

    // Which row's Remove/Block menu is open, if any - one at a time, since
    // it replaces that row's own preview line in place (see the delegate
    // below) rather than floating a popup the ListView's clip would cut off
    // the moment the row scrolls near an edge.
    property string menuForId: ""
    // Right arrow or Tab on a conversation: the thread is already open, now
    // put the cursor where you type. The pane owns the compose row, so this
    // is a request rather than a call.
    signal focusComposeAsked()

    function focusSearch(): void { queryField.forceActiveFocus(); }
    function focusList(): void { list.forceActiveFocus(); }

    // Where the selection is, derived rather than stored: the arrow keys
    // OPEN the thread they land on, so `activeId` already is the selection
    // and a second copy of it could only disagree.
    readonly property int selectedIndex: {
        for (let i = 0; i < root.listed.length; i++)
            if (root.listed[i].convId === root.activeId) return i;
        return -1;
    }

    // Where the selection should land when `convId` leaves the list: the
    // row after it, or the row before when it was last. "" only when it was
    // the only one.
    //
    // Asked of the VIEW and not of the model, because this is the order you
    // are looking at: `listed` is by recency and drops the removed and the
    // blocked, where model.conversations is pinned-first and keeps them.
    // Call it BEFORE the removal, while convId is still in the list.
    function neighbourOf(convId: string): string {
        let i = -1;
        for (let n = 0; n < root.listed.length; n++)
            if (root.listed[n].convId === convId) { i = n; break; }
        if (i < 0) return "";
        if (i + 1 < root.listed.length) return root.listed[i + 1].convId;
        if (i > 0) return root.listed[i - 1].convId;
        return "";
    }

    // One row up or down, clamped. Nothing selected yet lands on the first
    // row whichever way you pressed - the alternative is a first keypress
    // that does nothing at all.
    function step(delta: int): void {
        if (root.listed.length === 0) return;
        const next = Math.max(0, Math.min(root.listed.length - 1,
                                          root.selectedIndex + delta));
        if (next === root.selectedIndex) return;
        list.positionViewAtIndex(next, ListView.Contain);
        root.conversationPicked(root.listed[next].convId);
    }

    property string query: ""
    // A menu left open behind a new search is a menu nobody can see the
    // button for any more, since the row it belonged to may have scrolled
    // out of the filtered results entirely.
    onQueryChanged: root.menuForId = ""

    readonly property var pinned: root.conversations.filter(c =>
        c.pinned === true && c.removed !== true && c.blocked !== true)

    // Newest first. Pinned threads stay in the list as well as the grid:
    // promoting them out of it would mean a message from a pinned contact
    // arrived somewhere you were not looking.
    //
    // Removed/blocked conversations drop out of the passive list - that is
    // the whole point of removing or blocking one - but ONLY when there is
    // no query. Typing a name or number still has to find them: that is the
    // panel's own promise (docs/messages-panel.md says so in the UI copy
    // too), and losing a conversation to search just because it was hidden
    // would make "remove" indistinguishable from "delete forever".
    readonly property var listed: {
        const q = root.query.trim().toLowerCase();
        const all = root.conversations.slice();
        all.sort((a, b) => (b.ts || 0) - (a.ts || 0));
        if (!q) return all.filter(c => c.removed !== true && c.blocked !== true);
        return all.filter(c =>
            String(c.title || "").toLowerCase().indexOf(q) >= 0
            || String(c.number || "").toLowerCase().indexOf(q) >= 0
            || String(c.preview || "").toLowerCase().indexOf(q) >= 0
            // The preview is only the newest message; this is the rest of
            // the thread, as far as it has been cached.
            || root.bodyMatches.indexOf(c.convId) >= 0);
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

                // Down or Tab leaves the box for the list. Enter does too,
                // and selects the top hit if nothing is selected - having
                // typed a name, the next thing you want is that thread.
                Keys.onDownPressed: event => { event.accepted = true; root.focusList(); }
                Keys.onTabPressed: event => { event.accepted = true; root.focusList(); }
                Keys.onReturnPressed: event => {
                    event.accepted = true;
                    if (root.selectedIndex < 0) root.step(1);
                    root.focusList();
                }
                // Escape belongs to whoever collapses the pane. A TextInput
                // swallows it by default, which left Escape dead whenever
                // the cursor was in the search box.
                Keys.onEscapePressed: event => event.accepted = false

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
        // Two rows, exactly: two 88px cells plus the 14px between them. The
        // first version capped at 2*92 and clipped 6px off the bottom row's
        // names - visible only when a seventh pin made the grid scroll.
        readonly property real twoRows: (2 * 88 + 14) * root.uiScale
        height: Math.min(pinGrid.implicitHeight, twoRows)
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
        // A hard stop at the ends reads as stiff next to any trackpad-driven
        // scroll a person is used to (Firefox included) - letting it drag
        // past the bound and ease back is what makes the coast feel like
        // momentum rather than a wall.
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: 2500
        maximumFlickVelocity: 4000

        // The keyboard stop this pane opens on, so the arrows work before
        // anything has been clicked.
        focus: true
        // ListView's own key handling moves a currentIndex this list does
        // not use - the selection is activeId - and would also claim Home,
        // End and the page keys on the way past.
        keyNavigationEnabled: false

        Keys.onUpPressed: event => { event.accepted = true; root.step(-1); }
        Keys.onDownPressed: event => { event.accepted = true; root.step(1); }
        // Rightwards is into the thread you have selected - UNLESS the pane
        // has told us (via `root.arrowsBorrowed`) that the arrow is a skip
        // instead. Leaving the event unaccepted here lets it bubble to
        // MessagesPane, which performs the skip and owns the player; the
        // list itself only ever reads the decision, never recomputes it.
        Keys.onRightPressed: event => {
            if (root.arrowsBorrowed) { event.accepted = false; return; }
            event.accepted = true; root.focusComposeAsked();
        }
        Keys.onReturnPressed: event => { event.accepted = true; root.focusComposeAsked(); }
        Keys.onEnterPressed: event => { event.accepted = true; root.focusComposeAsked(); }
        Keys.onTabPressed: event => { event.accepted = true; root.focusComposeAsked(); }
        // ...and leftwards is back out to the search box, which is the only
        // thing to the left of a conversation row - same exception as above.
        Keys.onLeftPressed: event => {
            if (root.arrowsBorrowed) { event.accepted = false; return; }
            event.accepted = true; root.focusSearch();
        }
        Keys.onBacktabPressed: event => { event.accepted = true; root.focusSearch(); }

        delegate: Item {
            id: row
            required property var modelData
            width: list.width
            height: 56 * root.uiScale

            readonly property bool selected: modelData.convId === root.activeId
            readonly property bool menuOpen: modelData.convId === root.menuForId
            // moreArea OR'd in, not just rowArea: moreArea sits ON TOP of
            // rowArea (z: 2, right below) specifically so a click on the
            // button does not fall through - but that same stacking means
            // rowArea stops seeing hover the instant the cursor crosses onto
            // moreArea's bounds. Reading only rowArea.containsMouse made
            // `hovered` go false the moment the mouse reached the button,
            // which hid the button, which gave rowArea the hover back, which
            // showed it again - the button blinking under the cursor and a
            // click landing on whichever phase won the race, often rowArea's
            // own onClicked (opening the conversation) instead.
            readonly property bool hovered: rowArea.containsMouse || moreArea.containsMouse

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
                visible: !row.hovered && !row.menuOpen
                anchors.right: parent.right
                anchors.rightMargin: 16 * root.uiScale
                y: 9 * root.uiScale
                text: root.relativeTime(row.modelData.ts)
                color: "@mutedColor@"
                font.pixelSize: Math.round(10.5 * root.uiScale)
            }

            // The Remove/Block trigger, in the timestamp's own spot - shown
            // only on hover (or while its own menu is open, so moving the
            // mouse off the row to click a menu item does not hide the
            // button the menu hangs off of).
            Rectangle {
                id: moreBtn
                // Above rowArea (declared below, anchors.fill: parent),
                // which would otherwise win every click in this corner and
                // the button would never fire.
                z: 2
                visible: row.hovered || row.menuOpen
                anchors.right: parent.right
                anchors.rightMargin: 10 * root.uiScale
                y: 2 * root.uiScale
                width: 22 * root.uiScale
                height: 22 * root.uiScale
                radius: 7 * root.uiScale
                color: moreArea.containsMouse || row.menuOpen ? "@plateBg@" : "transparent"

                Panel.PanelIcon {
                    anchors.centerIn: parent
                    name: "more"
                    // 0.62, with the 2.2 dots PanelIcon now draws: ~2.7px
                    // dots on a 4px pitch in this 22px button. See the
                    // "more" case in PanelIcon for why the two numbers are
                    // one decision.
                    uiScale: root.uiScale * 0.62
                    color: "@mutedColor@"
                }

                MouseArea {
                    id: moreArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.menuForId = row.menuOpen ? "" : row.modelData.convId
                }
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
                visible: !row.menuOpen
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

            // Replaces the preview line in place while open - see
            // `menuForId`'s own comment for why this is not a floating
            // popup. Two plain text buttons rather than anything heavier:
            // this is a row inside a 340px sidebar, not a context menu with
            // room to spare.
            Row {
                // Same reasoning as moreBtn.z above - without it rowArea
                // eats every click meant for Remove/Block.
                z: 2
                visible: row.menuOpen
                x: who.x
                y: who.y + who.height + 1 * root.uiScale
                height: 28 * root.uiScale
                spacing: 8 * root.uiScale

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Remove"
                    color: "@mutedColor@"
                    font.pixelSize: Math.round(12 * root.uiScale)
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6 * root.uiScale
                        onClicked: {
                            root.menuForId = "";
                            root.removeAsked(row.modelData.convId);
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "·"
                    color: "@mutedColor@"
                    font.pixelSize: Math.round(12 * root.uiScale)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Block"
                    color: "@redColor@"
                    font.pixelSize: Math.round(12 * root.uiScale)
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6 * root.uiScale
                        onClicked: {
                            root.menuForId = "";
                            root.blockAsked(row.modelData.convId);
                        }
                    }
                }
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    root.menuForId = "";
                    if (mouse.button === Qt.RightButton) {
                        root.pinToggled(row.modelData.convId);
                        return;
                    }
                    // So the arrows carry on from where you clicked rather
                    // than from wherever the keyboard happened to be.
                    root.focusList();
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
