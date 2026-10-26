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
        // Body search only reaches what has been cached, and the empty state
        // has to say so rather than implying the message is not there.
        searchedBodies: false

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
            text: !root.core ? ""
                : root.core.conversations.length > 0
                    ? "Pick a conversation."
                    : root.core.connected
                        ? "No conversations yet."
                        : "No phone connected. Pair one in KDE Connect."
            color: "@mutedColor@"
            font.pixelSize: Math.round(13 * root.uiScale)
            wrapMode: Text.WordWrap
        }
    }
}
