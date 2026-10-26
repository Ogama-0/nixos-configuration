import QtQuick

// Messages, as a view. One of these per screen; the state lives in
// MessagesCore, which is instantiated once - see that file for why.
Item {
    id: root

    property real uiScale: 1
    property var core: null

    // Drives MessagesCore.active through whoever owns both, not from here:
    // two panes on two screens must not fight over one polling flag.
    property bool active: false

    // Set by the toast route to land straight on a thread.
    property string pendingConvId: ""

    signal closeAsked()

    readonly property bool hasThread: core && core.activeId !== ""

    function focusCompose(): void { compose.focusField(); }

    // The draft survives a collapse. Escape is how you leave this pane, and
    // losing half a typed message to it would make Escape frightening.
    property string keptDraft: ""

    onActiveChanged: {
        if (root.active) {
            compose.draft = root.keptDraft;
            root.consumePending();
        } else {
            root.keptDraft = compose.draft;
        }
    }

    onPendingConvIdChanged: root.consumePending()

    function consumePending(): void {
        if (!root.active || !root.pendingConvId || !root.core) return;
        root.core.openConversation(root.pendingConvId);
        root.pendingConvId = "";
    }

    // ---- the sidebar ----

    ThreadList {
        id: list
        x: 0
        y: 0
        width: 340 * root.uiScale
        height: parent.height
        uiScale: root.uiScale
        conversations: root.core ? root.core.conversations : []
        activeId: root.core ? root.core.activeId : ""
        // Body search reaches what has been cached and no further, and the
        // empty state says which kind of nothing it found.
        searchedBodies: false
        bodyMatches: root.core && query.length >= 2
            ? root.core.searchBodies(query) : []

        onConversationPicked: convId => { if (root.core) root.core.openConversation(convId) }
        onPinToggled: convId => { if (root.core) root.core.togglePin(convId) }
    }

    Rectangle {
        id: split
        x: list.width
        width: 1
        height: parent.height
        color: "@glassBorder@"
    }

    // ---- the thread ----

    ConversationView {
        id: thread
        visible: root.hasThread
        x: split.x + 1
        y: 0
        width: parent.width - x
        height: parent.height - compose.height
        uiScale: root.uiScale

        readonly property var conv: root.core
            ? root.core.conversationFor(root.core.activeId) : null

        title: conv ? conv.title : ""
        initials: conv ? conv.initials : ""
        hue: conv ? conv.hue : "@mutedColor@"
        messages: root.core ? root.core.activeMessages : []
        loadingOlder: root.core ? root.core.loadingOlder : false

        onOlderWanted: if (root.core) root.core.fetchOlder()
    }

    ComposeRow {
        id: compose
        visible: root.hasThread
        x: split.x + 1
        y: parent.height - height
        width: parent.width - x
        uiScale: root.uiScale
        enabled: root.core ? root.core.connected : false

        onSendRequested: (text, attachments) => {
            if (root.core) root.core.send(text, attachments);
        }
    }

    // Nothing open yet. An invitation, not a blank half-screen.
    Item {
        visible: !root.hasThread
        x: split.x + 1
        y: 0
        width: parent.width - x
        height: parent.height

        Text {
            anchors.centerIn: parent
            width: parent.width * 0.6
            horizontalAlignment: Text.AlignHCenter
            // "Pair one in KDE Connect" is the wrong thing to tell someone
            // whose phone IS paired and merely asleep - it asks them to do
            // something they have already done.
            text: !root.core ? ""
                : root.core.conversations.length > 0
                    ? "Pick a conversation."
                    : !root.core.known
                        ? "No phone paired. Pair one in KDE Connect."
                        : !root.core.connected
                            ? "Your phone is not on the network. Anything already downloaded is still here."
                            : "No conversations yet."
            color: "@mutedColor@"
            font.pixelSize: Math.round(13 * root.uiScale)
            wrapMode: Text.WordWrap
        }
    }
}
