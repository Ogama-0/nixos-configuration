import QtQuick

// Messages, whole: the sidebar, the thread, and the one place that owns the
// models everything else is handed.
//
// This is the wiring point on purpose. ContactsModel, MessageHue,
// MessageStore and MessagesModel are instantiated here and nowhere else, and
// the views below receive values rather than reaching for a model. That is
// what lets MessageAvatar sit inside a ListView delegate without having a
// model threaded down to it, and what lets every fixture drive a view with
// fixed data.
Item {
    id: root

    property real uiScale: 1

    // Gates everything underneath: no monitor, no subprocesses, no polling
    // while the pane is closed.
    property bool active: false
    property string deviceId: ""

    // Set by the toast route to land straight on a thread.
    property string pendingConvId: ""

    signal closeAsked()

    readonly property bool hasThread: model.activeId !== ""

    function openConversation(convId: string): void {
        model.openConversation(convId);
    }

    function focusCompose(): void { compose.focusField(); }

    // The draft survives a collapse. Escape is how you leave this pane, and
    // losing half a typed message to it would make Escape frightening.
    property string keptDraft: ""

    onActiveChanged: {
        model.active = root.active;
        contacts.load(root.deviceId);
        if (root.active) {
            compose.draft = root.keptDraft;
            if (root.pendingConvId) {
                model.openConversation(root.pendingConvId);
                root.pendingConvId = "";
            }
        } else {
            root.keptDraft = compose.draft;
        }
    }

    onPendingConvIdChanged: {
        if (root.active && root.pendingConvId) {
            model.openConversation(root.pendingConvId);
            root.pendingConvId = "";
        }
    }

    // ---- the models, owned here ----

    ContactsModel { id: contacts }
    MessageHue { id: hues }
    MessageStore { id: store; Component.onCompleted: init() }

    MessagesModel {
        id: model
        deviceId: root.deviceId
        contacts: contacts
        palette: hues
        store: store
    }

    // Names arrive after the vCards have been read, which is after the first
    // conversations have landed. Without this the list keeps whatever it was
    // built with - every thread titled by its phone number.
    Connections {
        target: contacts
        function onReadyChanged() { if (contacts.ready) model.relabel(); }
    }

    // ---- the sidebar ----

    ThreadList {
        id: list
        x: 0
        y: 0
        width: 340 * root.uiScale
        height: parent.height
        uiScale: root.uiScale
        conversations: model.conversations
        activeId: model.activeId
        // Body search only reaches what has been cached, and the empty state
        // has to say so rather than implying the message is not there.
        searchedBodies: false

        onConversationPicked: convId => model.openConversation(convId)
        onPinToggled: convId => {
            const pinned = store.pinnedIds().indexOf(convId) >= 0;
            store.setPinned(convId, !pinned);
            model.reloadFlags();
        }
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

        readonly property var conv: model.conversations
            .filter(c => c.convId === model.activeId)[0]

        title: conv ? conv.title : ""
        initials: conv ? conv.initials : ""
        hue: conv ? conv.hue : "@mutedColor@"
        messages: model.activeMessages
        loadingOlder: model.loadingOlder

        onOlderWanted: model.fetchOlder()
    }

    ComposeRow {
        id: compose
        visible: root.hasThread
        x: split.x + 1
        y: parent.height - height
        width: parent.width - x
        uiScale: root.uiScale
        enabled: model.connected

        onSendRequested: (text, attachments) => model.send(text, attachments)
    }

    // Nothing open yet. An invitation, not a blank half-screen.
    Item {
        visible: !root.hasThread
        x: split.x + 1
        y: 0
        width: parent.width - x
        height: parent.height

        Column {
            anchors.centerIn: parent
            width: parent.width * 0.6
            spacing: 8 * root.uiScale

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: model.conversations.length > 0
                    ? "Pick a conversation."
                    : model.connected
                        ? "No conversations yet."
                        : "No phone connected. Pair one in KDE Connect."
                color: "@mutedColor@"
                font.pixelSize: Math.round(13 * root.uiScale)
                wrapMode: Text.WordWrap
            }
        }
    }
}
