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

    function openConversation(convId: string): void { model.openConversation(convId) }
    function fetchOlder(): void { model.fetchOlder() }
    function send(text: string, attachments: var): string {
        return model.send(text, attachments);
    }

    function conversationFor(convId: string): var {
        return model.conversations.filter(c => c.convId === convId)[0];
    }

    function togglePin(convId: string): void {
        const pinned = store.pinnedIds().indexOf(convId) >= 0;
        store.setPinned(convId, !pinned);
        model.reloadFlags();
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
        contacts: contacts
        palette: hues
        store: store
        active: root.active
        listening: root.listening
        onMessageArrived: msg => root.messageArrived(msg)
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
