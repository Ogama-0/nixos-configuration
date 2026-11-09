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
    // Forwarded untouched from ConversationView - see its own comment on
    // the signal of the same name for what `origin` is expressed in.
    signal pictureAsked(string source, string who, real ts, rect origin)

    readonly property bool hasThread: core && core.activeId !== ""

    function focusCompose(): void { compose.focusField(); }

    // The pane opens with the conversation list live, so the arrow keys work
    // before anything has been clicked. It is the only surface up and it
    // already holds the keyboard exclusively - see the focus section of
    // docs/messages-panel.md - so there is nothing here to steal focus from.
    function focusList(): void { list.focusList(); }

    // While a voice note plays, the left/right arrows become a ±5s skip
    // everywhere EXCEPT the compose field. In a draft the left arrow is the
    // text cursor (ComposeRow already protects that - see its own Left
    // handler), and listening to a note while typing a reply is ordinary;
    // taking the caret keys away mid-draft to serve a shortcut would be
    // worse than not having the shortcut. So the borrow only applies when
    // the compose field does NOT hold the keyboard - the thread list, or
    // nothing focused at all.
    //
    // Pure on purpose: the nav fixture calls this directly (it cannot
    // synthesise a key press - see its header), so the decision has to be
    // a function rather than buried in a Keys handler.
    function arrowsBorrowed(playingId: string, composeFocused: bool): bool {
        return playingId !== "" && !composeFocused;
    }

    // The one live evaluation of the decision above, bound down into
    // ThreadList (`list.arrowsBorrowed` below) so its Right/Left handlers
    // only ever read it rather than recomputing their own half of it - one
    // source of truth instead of two that happen to agree today.
    readonly property bool arrowsBorrowedNow:
        root.arrowsBorrowed(root.core && root.core.audio ? root.core.audio.playingId : "",
                             compose.fieldFocused)

    // ThreadList's own Right/Left (see its Keys handlers) leave the event
    // unaccepted exactly when `arrowsBorrowedNow` is true, so it bubbles up
    // here. The compose field's Left handler never does that - it either
    // moves the cursor or goes back to the list on its own - which is how
    // this never fires while compose holds the keyboard without this file
    // having to ask it.
    Keys.onLeftPressed: event => {
        if (!root.arrowsBorrowedNow) return;
        root.core.audio.skip(-5000);
        event.accepted = true;
    }
    Keys.onRightPressed: event => {
        if (!root.arrowsBorrowedNow) return;
        root.core.audio.skip(5000);
        event.accepted = true;
    }

    // Suppr, while a thread is open: removes the conversation you are
    // looking at and drops you back on the list.
    //
    // Gated on the LIST actually holding the keyboard, rather than on
    // everything else happening to swallow Delete first. That assumption
    // held while the only focusable things in here were two text fields
    // (which consume it as an editing key) - but the message bubbles are
    // read-only TextEdits now, and a read-only TextEdit IGNORES Delete, so
    // it bubbled up here and removed the conversation out from under
    // somebody who had clicked into a message to copy a word of it.
    Keys.onDeletePressed: event => {
        if (!list.activeFocus) return;
        if (!root.hasThread || !root.core) return;
        event.accepted = true;
        const id = root.core.activeId;
        root.core.removeConversation(id, list.neighbourOf(id));
    }

    // The draft survives a collapse. Escape is how you leave this pane, and
    // losing half a typed message to it would make Escape frightening.
    property string keptDraft: ""

    onActiveChanged: {
        if (root.active) {
            compose.draft = root.keptDraft;
            root.consumePending();
            // Not a direct call. `active` and the surface's
            // WlrKeyboardFocus.Exclusive grant (ControlPanel.qml) both flip
            // off the same `messagesOpen` change, but the real Wayland focus
            // grant is a compositor round-trip and this handler runs
            // synchronously on the same tick - forceActiveFocus() landed
            // before the surface actually held the keyboard, so the first
            // arrow press went nowhere until a click (which calls focusList()
            // again on its own) gave the list focus for real. One tick is
            // enough for the grant to land.
            focusSettle.restart();
        } else {
            root.keptDraft = compose.draft;
        }
    }

    Timer {
        id: focusSettle
        // A real Wayland round-trip, not a same-tick requeue like
        // syncSwayModeTimer's 0ms - the compositor has to actually hand the
        // surface the keyboard before forceActiveFocus() sticks. One frame
        // is enough margin without being a felt delay.
        interval: 30
        repeat: false
        // root.active can have flipped back off in the 30ms since restart()
        // was called (a fast toggle) - stealing focus onto an already-closed
        // pane is worse than just skipping the grab.
        onTriggered: if (root.active) root.focusList()
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
        // The single source of truth (`arrowsBorrowedNow` above) bound down,
        // so the list's own Right/Left handlers only read the decision
        // instead of recomputing their own half of it.
        arrowsBorrowed: root.arrowsBorrowedNow

        onConversationPicked: convId => { if (root.core) root.core.openConversation(convId) }
        onPinToggled: convId => { if (root.core) root.core.togglePin(convId) }
        // The neighbour is read HERE, before the removal, because after it
        // the row is gone from `listed` and there is nothing left to be
        // next to.
        onRemoveAsked: convId => {
            if (root.core) root.core.removeConversation(convId, list.neighbourOf(convId));
        }
        onBlockAsked: convId => {
            if (root.core) root.core.blockConversation(convId, list.neighbourOf(convId));
        }
        // Right arrow or Tab on a row. Nothing to focus if no thread is
        // open, and the field is not even visible then.
        onFocusComposeAsked: if (root.hasThread) compose.focusField()
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
        audio: root.core ? root.core.audio : null

        onOlderWanted: if (root.core) root.core.fetchOlder()
        onAttachmentAsked: (partId, uid) => {
            if (root.core) root.core.fetchAttachment(partId, uid);
        }
        onPictureAsked: (source, who, ts, origin) =>
            root.pictureAsked(source, who, ts, origin)
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
        onBackFocusAsked: list.focusList()
        onSearchFocusAsked: list.focusSearch()
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
