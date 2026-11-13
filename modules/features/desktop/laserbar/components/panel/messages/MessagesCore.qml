import QtQuick

// Everything Messages knows, owned once.
//
// This exists because ControlPanel's window is inside a Variants over
// Quickshell.screens - one PanelWindow per monitor. The first version put
// the models inside the pane, which meant a two-monitor session got two
// SQLite connections, two reads of the 229 vCards, and two `busctl monitor`
// processes both ingesting every message.
//
// So the split is the same one the rest of the panel already uses -
// MobileModel/MobilePane, DiskModel/DiskPane: one non-visual thing holding
// the state, instantiated at the top, and a view per screen bound to it.
Item {
    id: root

    property string deviceId: ""
    property bool reachable: false

    // Polling. Only while a pane is actually open.
    property bool active: false
    // The signal monitor, which has to outlive the pane or a text arriving
    // with the panel shut would never raise a toast.
    property bool listening: true

    signal messageArrived(var msg)

    readonly property alias conversations: model.conversations
    readonly property alias activeId: model.activeId
    readonly property alias activeMessages: model.activeMessages
    readonly property alias loadingOlder: model.loadingOlder
    readonly property alias connected: model.connected
    // Paired at all. Drives whether Messages can be opened to browse the
    // cache, as opposed to whether anything can be sent.
    readonly property bool known: root.deviceId !== ""

    readonly property alias audio: audio

    function openConversation(convId: string): void {
        // A voice note from the PREVIOUS thread playing under the new one is
        // the one audio player's whole failure mode without this - see
        // MessageAudio's REVIEW FOCUS 4.
        audio.stop();
        model.openConversation(convId);
    }
    function fetchOlder(): void { model.fetchOlder() }
    function fetchAttachment(partId: int, uid: string): void {
        model.fetchAttachment(partId, uid);
    }
    function send(text: string, attachments: var): string {
        return model.send(text, attachments);
    }

    // Conversation ids whose CACHED message bodies match. Only threads that
    // have been opened are in the index - the rest of the history is still on
    // the phone - which is why the sidebar says so rather than implying the
    // message is not there.
    function searchBodies(query: string): var {
        if (!query || query.trim().length < 2) return [];
        const hits = store.search(query, 80);
        let seen = {};
        let out = [];
        for (const h of hits) {
            if (seen[h.convId]) continue;
            seen[h.convId] = true;
            out.push(h.convId);
        }
        return out;
    }

    function conversationFor(convId: string): var {
        return model.conversations.filter(c => c.convId === convId)[0];
    }

    function togglePin(convId: string): void {
        const pinned = store.pinnedIds().indexOf(convId) >= 0;
        store.setPinned(convId, !pinned);
        model.reloadFlags();
    }

    // Hides the conversation now; a fresh incoming message un-hides it on
    // its own - see MessageStore.setRemoved and MessagesModel.ingestMessage.
    // `nextId` is where the selection should land if `convId` was the open
    // one - the caller works it out from the list on screen (see
    // ThreadList.neighbourOf). "" means "nothing open", which is right when
    // the one removed was the last conversation there was.
    function removeConversation(convId: string, nextId: string): void {
        store.setRemoved(convId, true);
        model.reloadFlags();
        root.stepOutIfActive(convId, nextId);
    }

    // Hides it AND drops every future message for the number on arrival -
    // see MessageStore.setBlocked and the blockedIds() check in
    // MessagesModel.ingestMessage/ingestBatch.
    function blockConversation(convId: string, nextId: string): void {
        store.setBlocked(convId, true);
        model.reloadFlags();
        root.stepOutIfActive(convId, nextId);
    }

    // Hiding a thread says nothing about whether you are SITTING IN IT, and
    // both functions above are reachable from a row's own menu while that
    // row is the open one. The guard belongs HERE rather than in the key
    // handler that first needed it: it used to be the keyboard path alone,
    // so Suppr stepped out and the identical action from the mouse did not.
    //
    // What that left behind: the row leaves the sidebar while
    // ConversationView carries on showing the thread, with a live compose
    // field still pointed at a number that - in the Block case - was just
    // blocked. `activeId` is also no longer findable in ThreadList.listed,
    // so its selectedIndex goes to -1 and the next arrow key jumps to the
    // top of the list instead of the removed row's neighbour.
    //
    // SIDEWAYS, not out. Landing on nothing meant the selection was gone
    // (ThreadList.selectedIndex goes to -1 with no activeId), so the next
    // arrow key jumped to the top of the list - remove two neighbours and
    // you walked back down from the top twice. The row that took its place
    // on screen is the one you were already looking at.
    //
    // root.openConversation, not model's: the wrapper is where audio.stop()
    // lives, and a voice note from the thread you just removed must not go
    // on sounding underneath the thread that replaced it.
    function stepOutIfActive(convId: string, nextId: string): void {
        if (convId && convId === model.activeId)
            root.openConversation(nextId || "");
    }

    // Answer without opening anything. The toast's whole purpose.
    function replyTo(convId: string, text: string): void {
        const was = model.activeId;
        model.activeId = convId;
        model.send(text, []);
        model.activeId = was;
    }

    ContactsModel { id: contacts }
    MessageHue { id: hues }
    MessageStore { id: store; Component.onCompleted: init() }

    MessagesModel {
        id: model
        deviceId: root.deviceId
        reachable: root.reachable
        contacts: contacts
        palette: hues
        store: store
        active: root.active
        listening: root.listening
        onMessageArrived: msg => root.messageArrived(msg)
        onAttachmentReady: (uid, path) => audio.fileArrived(uid, path)
    }

    // Owned here for the same reason contacts/hues/store are: one per shell,
    // not one per screen's pane, or two monitors would fight over the same
    // sound-card handle (spec, Design). fetchAsked's partId is the real
    // attachment part id by the time it reaches here - toggle()'s caller
    // (the voice bubble) holds the attachment struct and passes it through.
    MessageAudio {
        id: audio
        store: store
        onFetchAsked: (partId, uid) => model.fetchAttachment(partId, uid)
    }

    // Read even with every pane shut, or a toast names the sender by their
    // phone number.
    Component.onCompleted: contacts.load(root.deviceId)
    onDeviceIdChanged: contacts.load(root.deviceId)

    // The vCards finish loading after the first conversations have landed,
    // so threads get built titled by their numbers. Without this they keep
    // them until the next message arrives - for a quiet thread, never.
    Connections {
        target: contacts
        function onReadyChanged() { if (contacts.ready) model.relabel(); }
    }
}
