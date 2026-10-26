import QtQuick
import Quickshell
import Quickshell.Io

// The phone's messages, over KDE Connect. Non-visual.
//
// Two DBus objects, and the useful one is not the obvious one. You ASK on
// /modules/kdeconnect/devices/<id>/sms, but everything comes back on the
// device object itself under org.kde.kdeconnect.device.conversations - an
// interface that does not exist at all until the phone has answered once.
// Full field table in docs/kdeconnect-sms-payload.md.
//
// Replies are signals, not return values, so there is a `busctl monitor`
// running for as long as the pane is open and nothing at all when it is not.
//
// Everything lands in MessageStore on the way past. The pane reads the store,
// never this, so a thread opens at cache speed and fills in when the phone
// gets round to it.
Item {
    id: root

    // Gates every subprocess. Closed pane, no monitor, no polling.
    property bool active: false
    // Fixtures set this false and drive ingest* directly.
    property bool transportEnabled: true

    property string deviceId: ""
    property bool connected: deviceId !== ""

    // Injected rather than owned, so one ContactsModel and one MessageHue
    // serve the pane, the toasts and anything else - and so a fixture can
    // hand over a stub instead of 229 files on disk.
    property var contacts: null
    property var palette: null
    property var store: null

    // [{ convId, title, addresses, isGroup, preview, ts, unread, pinned,
    //    initials, hue }] - pinned first, then newest.
    property var conversations: []

    property string activeId: ""
    property var activeMessages: []
    property bool loadingOlder: false

    // Bumped on every page request. The fixture asserts on it because
    // "did not ask twice" is the actual contract, not "did not crash".
    property int fetchCount: 0

    signal messageArrived(var record)

    readonly property string devPath: "/modules/kdeconnect/devices/" + deviceId
    readonly property string convIface: "org.kde.kdeconnect.device.conversations"

    // Threads we have seen, by id. Kept separately from `conversations` so
    // rebuilding the sorted list is a map over this rather than a merge into
    // an array that is also being read by a ListView.
    property var threads: ({})

    // ---- parsing ----

    // One ConversationMessage, as the ten-field struct documented in
    // docs/kdeconnect-sms-payload.md.
    function parseMessage(m: var): var {
        const addresses = (m[2] || []).map(a => Array.isArray(a) ? a[0] : a);
        return {
            eventField: m[0],
            body: m[1] || "",
            addresses: addresses,
            ts: m[3],
            // Android's SMS type: 1 inbox, 2 sent. Not a boolean on the wire.
            outgoing: m[4] === 2,
            read: m[5] === 1,
            convId: String(m[6]),
            id: String(m[7]),
            subId: m[8],
            attachments: (m[9] || []).map(a => ({
                partId: a[0], mime: a[1], data: a[2], uid: a[3],
                // Filled in by attachmentReceived; empty means "still on the
                // phone", which the view renders as such rather than as a
                // broken image.
                path: ""
            }))
        };
    }

    // A message with no body is not a message with nothing in it - MMS voice
    // notes and photos arrive with body "" - so the list needs something to
    // show that is not a blank line.
    function previewFor(msg: var): string {
        if (msg.body) return msg.body;
        if (msg.attachments.length > 0) {
            const mime = String(msg.attachments[0].mime || "");
            if (mime.startsWith("image/")) return "Photo";
            if (mime.startsWith("audio/")) return "Voice message";
            if (mime.startsWith("video/")) return "Video";
            return "Attachment";
        }
        return "";
    }

    function ingestMessage(raw: var): void {
        const msg = root.parseMessage(raw);
        if (root.store) root.store.putMessages(msg.convId, [msg]);

        const prev = root.threads[msg.convId];
        // Only the newest message names the thread and writes the preview; a
        // page of history scrolling in must not rewrite the list.
        const newer = !prev || msg.ts >= prev.ts;

        const primary = msg.addresses.length > 0 ? msg.addresses[0] : "";
        const who = root.contacts ? root.contacts.resolve(primary)
                                  : { name: primary, initials: "" };

        root.threads[msg.convId] = {
            convId: msg.convId,
            title: newer || !prev ? who.name : prev.title,
            initials: newer || !prev ? who.initials : prev.initials,
            hue: root.palette ? root.palette.hueFor(primary) : "#FF888888",
            addresses: newer || !prev ? msg.addresses : prev.addresses,
            isGroup: newer || !prev ? msg.addresses.length > 1 : prev.isGroup,
            preview: newer || !prev ? root.previewFor(msg) : prev.preview,
            ts: newer || !prev ? msg.ts : prev.ts,
            // Unread is ours, not the phone's, past this first sighting:
            // there is no markRead on the interface, so once we have decided
            // a thread is read the phone cannot argue.
            unread: prev ? prev.unread : !msg.read,
            pinned: prev ? prev.pinned : false
        };

        if (msg.convId === root.activeId) root.refreshActive();
        root.rebuild();
        root.messageArrived(msg);
    }

    // Re-reads pins and unread out of the store. Cheap, and called whenever
    // something outside this object has changed one of them.
    function reloadFlags(): void {
        if (!root.store) { root.rebuild(); return; }
        const pins = root.store.pinnedIds();
        const unread = root.store.unreadIds();
        for (const id in root.threads) {
            root.threads[id].pinned = pins.indexOf(id) >= 0;
            root.threads[id].unread = unread.indexOf(id) >= 0
                || root.threads[id].unread;
        }
        root.rebuild();
    }

    // Pinned first in pin order, then everything by recency. Pinned threads
    // stay in the list as well as the grid - see ThreadList.
    function rebuild(): void {
        const pins = root.store ? root.store.pinnedIds() : [];
        let out = [];
        for (const id in root.threads) out.push(root.threads[id]);
        out.sort((a, b) => {
            const pa = pins.indexOf(a.convId), pb = pins.indexOf(b.convId);
            if (pa >= 0 && pb < 0) return -1;
            if (pb >= 0 && pa < 0) return 1;
            if (pa >= 0 && pb >= 0) return pa - pb;
            return (b.ts || 0) - (a.ts || 0);
        });
        root.conversations = out;
    }

    // ---- opening a thread ----

    function refreshActive(): void {
        if (!root.store || !root.activeId) { root.activeMessages = []; return; }
        root.activeMessages = root.store.messages(root.activeId,
                                                  root.store.pageSize, 0);
    }

    function openConversation(convId: string): void {
        root.activeId = convId;
        if (root.store) {
            root.store.touch(convId, 0);
            root.store.setUnread(convId, false);
        }
        if (root.threads[convId]) {
            root.threads[convId].unread = false;
            root.rebuild();
        }
        // Cache first, always. The phone is allowed to be slow; the pane is
        // not allowed to be blank while it thinks.
        root.refreshActive();
        root.requestPage(0, root.store ? root.store.pageSize : 30);
    }

    // start/end are INDEXES into the thread, newest first. The /sms object's
    // requestConversation takes a timestamp; this interface does not, and
    // this is the interface that answers.
    function requestPage(start: int, count: int): void {
        root.fetchCount += 1;
        if (!root.transportEnabled || !root.connected || !root.activeId) return;
        root.loadingOlder = true;
        pageProc.command = ["busctl", "--user", "call", "org.kde.kdeconnect",
            root.devPath, root.convIface, "requestConversation", "xii",
            root.activeId, String(start), String(start + count - 1)];
        pageProc.running = true;
    }

    function fetchOlder(): void {
        if (root.loadingOlder) return;
        const have = root.activeMessages.length;
        root.requestPage(have, root.store ? root.store.pageSize : 30);
    }

    // ---- sending ----

    // replyToConversation, not sendSms: the thread id is what we have, and
    // this is the call the conversations interface offers for it.
    //
    // There is no receipt. Nothing returns, and nothing confirms - the
    // message is only real once the phone echoes it back as a
    // conversationUpdated. Until then the bubble says so.
    function send(text: string, attachments: var): string {
        const pendingId = "pending-" + Date.now();
        if (!root.activeId) return pendingId;
        // An empty field is not a message. Enter on an empty compose box is
        // the commonest way to hit this, and a blank bubble that can never
        // be confirmed would sit in the thread forever.
        const hasAttachments = (attachments || []).length > 0;
        if (!String(text).trim() && !hasAttachments) return "";

        const atts = (attachments || []).map(a => String(a));
        let cmd = ["busctl", "--user", "call", "org.kde.kdeconnect",
                   root.devPath, root.convIface, "replyToConversation",
                   "xsav", root.activeId, text, String(atts.length)];
        for (const a of atts) cmd = cmd.concat(["s", a]);

        // Shown immediately, marked pending. If the phone never echoes it
        // back it stays pending, which is the honest state - it is not
        // promoted on a timer.
        if (root.store) {
            root.store.putMessages(root.activeId, [{
                id: pendingId, convId: root.activeId, body: text,
                ts: Date.now(), outgoing: true,
                address: "", attachments: []
            }]);
            root.refreshActive();
        }

        if (root.transportEnabled && root.connected) {
            sendProc.command = cmd;
            sendProc.running = true;
        }
        return pendingId;
    }

    function fetchAttachment(partId: int, uid: string): void {
        if (!root.transportEnabled || !root.connected) return;
        attProc.command = ["busctl", "--user", "call", "org.kde.kdeconnect",
            root.devPath, root.convIface, "requestAttachmentFile",
            "xs", String(partId), uid];
        attProc.running = true;
    }

    // ---- transport ----

    function refresh(): void {
        if (!root.transportEnabled || !root.connected) return;
        listProc.command = ["busctl", "--user", "--json=short", "call",
            "org.kde.kdeconnect", root.devPath, root.convIface,
            "activeConversations"];
        listProc.running = true;
    }

    Process { id: pageProc }
    Process { id: sendProc }
    Process { id: attProc }

    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(this.text).data[0];
                    for (const entry of payload) root.ingestMessage(entry.data);
                } catch (e) {
                    // No SMS plugin, no permission, a phone that wandered
                    // off: the pane shows what it has cached and says the
                    // phone is away. It does not invent a conversation.
                }
            }
        }
    }

    // The signal side. One long-lived monitor for as long as the pane is
    // open, filtered down to the conversations interface - the session bus
    // carries a lot of traffic that is none of our business.
    Process {
        id: monitorProc
        running: root.active && root.transportEnabled && root.connected
        command: ["busctl", "--user", "--json=short", "monitor",
                  "org.kde.kdeconnect"]
        stdout: SplitParser {
            onRead: line => {
                let ev;
                try { ev = JSON.parse(line); } catch (e) { return; }
                if (ev.type !== "signal" || ev.interface !== root.convIface) return;

                if (ev.member === "conversationCreated"
                    || ev.member === "conversationUpdated") {
                    // The variant wraps the struct; the struct's data is the
                    // ten-field array.
                    const v = ev.payload && ev.payload.data;
                    const msg = v && v.data ? v.data : v;
                    if (msg) root.ingestMessage(msg);
                } else if (ev.member === "conversationLoaded") {
                    // A completion notice carrying no content: the page we
                    // asked for has finished arriving message by message.
                    root.loadingOlder = false;
                    root.refreshActive();
                } else if (ev.member === "conversationRemoved") {
                    const id = String(ev.payload.data[0]);
                    delete root.threads[id];
                    root.rebuild();
                } else if (ev.member === "attachmentReceived") {
                    root.refreshActive();
                }
            }
        }
    }

    // Retention runs once, when the model wakes up. Not on a timer: nothing
    // about a 30-day window needs to be noticed within the minute.
    property bool evicted: false
    onActiveChanged: {
        if (!active || root.evicted) return;
        root.evicted = true;
        if (root.store) root.store.evictStale();
        root.refresh();
    }
}
