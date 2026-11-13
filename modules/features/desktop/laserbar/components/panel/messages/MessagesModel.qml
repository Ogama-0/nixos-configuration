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

    // Gates the things that cost something per use: the conversation-list
    // refresh and the page requests. Closed pane, no polling.
    property bool active: false

    // The signal monitor, separately, because you cannot toast a message you
    // were not listening for. One idle `busctl monitor` is the price of a
    // text arriving while the panel is shut, and it replaces polling rather
    // than adding to it.
    property bool listening: false
    // Fixtures set this false and drive ingest* directly.
    property bool transportEnabled: true

    // Which phone. Set from the PAIRED device, not the reachable one - it is
    // what names the cache's contacts and builds the DBus paths, and it
    // stays valid while the phone is asleep.
    property string deviceId: ""

    // Whether that phone is actually on the network. A separate input
    // because `kdeconnect-cli -a` lists only reachable devices, so a paired
    // phone that has wandered off reports nothing at all - and inferring
    // reachability from "do we have an id" took the cache away with it.
    property bool reachable: false

    // Only when both: we know who, and they are there.
    readonly property bool connected: deviceId !== "" && reachable

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
    // The index the last page was asked for, which is the thing that was
    // wrong rather than the number of requests.
    property int lastStart: -1
    // And where it stopped, which is exclusive.
    property int lastEnd: -1

    // How many messages of the open thread to show.
    //
    // NOT a constant page. refreshActive() used to re-read the newest page
    // and assign it over the top of everything, so the page fetchOlder() had
    // just written into SQLite was thrown away on arrival and a thread was
    // capped at @msgPageSize@ messages however far you scrolled.
    property int pageLimit: 0

    signal messageArrived(var record)
    // Raised alongside the store write below, so whatever is waiting on a
    // voice note (MessageAudio.fileArrived, via MessagesCore) hears about it
    // without reaching into the store itself or re-parsing the bus payload.
    signal attachmentReady(string uid, string path)

    readonly property string convIface: "org.kde.kdeconnect.device.conversations"

    // Built when the command is built, NOT held as a binding.
    //
    // It was `readonly property string devPath: ".../devices/" + deviceId`,
    // and `connected` is a second binding on that same deviceId.
    // onConnectedChanged runs as soon as `connected` settles, which is not
    // after every other binding on deviceId has caught up - so the retry that
    // exists precisely for a phone arriving late (MobileModel takes a couple
    // of seconds to shell out to kdeconnect-cli) read the path built while
    // deviceId was still "" and went out as
    //
    //   busctl call ... /modules/kdeconnect/devices/   -> Invalid object path
    //
    // exit 1, nothing on stdout, JSON.parse threw into a catch that is
    // deliberately silent. The pane said "No conversations yet." next to a
    // reachable phone holding fifty-one conversations. Deriving it from the
    // id at call time removes the ordering question rather than answering it.
    function devPathFor(id: string): string {
        root.lastPath = "/modules/kdeconnect/devices/" + id;
        return root.lastPath;
    }

    // The path the last command was built with. Exists so a fixture can see
    // the thing that was wrong; nothing reads it at runtime.
    property string lastPath: ""

    // Message ids we already hold, so a re-announced message does not toast
    // a second time. Bounded by the retention window in practice - the store
    // is what remembers across restarts; this only has to survive a session.
    property var seen: ({})

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

    // `fromSignal` is the difference between news and catching up.
    //
    // A conversationCreated off the wire is something that just happened and
    // deserves a toast. The 50 conversations that come back from a refresh
    // every time the pane opens are the same texts you read days ago, and
    // toasting them was the panel shouting your whole inbox at you on every
    // single open.
    function ingestMessage(raw: var, fromSignal: bool): void {
        // Not everything on that bus is a ConversationMessage. One payload
        // of some other shape reached the real cache and sat in it as a row
        // with id "undefined", which is a message in no thread at all.
        if (!root.usable(raw)) return;
        const msg = root.parseMessage(raw);
        // Seen before? Then whatever this is, it is not news. The daemon
        // re-emits conversationCreated for threads it already told us about
        // while a refresh is in flight, so "arrived as a signal" is not
        // enough on its own.
        //
        // Asked of the STORE as well as of this session, because a session
        // starts on every reboot and every rebuild while the cache does not.
        // primeThreads() answers as a burst of fifty conversationCreated -
        // the newest message of every thread - and against an empty `seen`
        // all of them read as fresh and toasted texts read days ago.
        const fresh = root.seen[msg.id] === undefined
            && !(root.store && root.store.has(msg.id));
        root.seen[msg.id] = true;

        if (root.store) {
            root.store.putMessages(msg.convId, [msg]);
            // This may BE the echo of something we sent. The pending copy
            // goes once the real one is in, or the thread shows both.
            if (msg.outgoing)
                root.store.resolvePending(msg.convId, msg.body, msg.ts, msg.id);
        }

        // ONE flag read for this message, shared by the block guard, the
        // un-hide and fold() below - the same reason ingestBatch reads it
        // once for a whole batch, and for the same traffic: a page arrives
        // as one conversationUpdated PER MESSAGE and primeThreads() as a
        // burst of fifty conversationCreated, so every query here is paid
        // thirty or fifty times over, on the UI thread, while the open
        // animation runs. This was a blockedIds() call of its own plus a
        // flagsFor() on the fold line, which ran blockedIds twice and - with
        // rebuild() below asking again - pinnedIds twice as well.
        const flags = root.flagsFor();

        // Blocked means never again, not "until the next text" - the row
        // stays folded out of `threads` entirely (so no toast, no list
        // entry) even though the message above was just written to disk.
        // Unblocking (not reachable from the UI yet) finds the history
        // waiting for it rather than a gap.
        if (flags.blocked.indexOf(msg.convId) >= 0) return;

        // Is this NEWS, or is it history arriving?
        //
        // `fresh` above only means "never seen this uID", which a page of
        // scrollback satisfies completely: requestConversation answers with
        // one conversationUpdated PER MESSAGE, all fromSignal, and for a
        // thread whose history was never cached every one of them is fresh.
        // So `fromSignal && fresh` cannot by itself tell a text that just
        // landed from the backlog we asked for - and both things below
        // depended on it being able to.
        //
        // History is, by definition, older than the newest message already
        // held for the thread. STRICTLY older: the daemon re-announces that
        // same newest message at the head of every page, and a re-
        // announcement is not news either. A thread never seen at all has no
        // newest message to be older than, so its first message is news.
        const known = root.threads[msg.convId];
        const isNews = !known || msg.ts > known.ts;

        // A genuinely new message is the one thing that un-hides a REMOVED
        // (not blocked) conversation - see MessageStore.setRemoved's own
        // comment, which promises it is NEVER cleared by opening the thread
        // from search.
        //
        // Keeping that promise needs `isNews`, not just fromSignal && fresh:
        // opening a removed thread from search fires a page request, the
        // page comes back as thirty fresh signals, and the conversation
        // un-hid itself - precisely the thing the comment says cannot
        // happen.
        //
        // And only when it IS removed. This used to write unconditionally,
        // which is a SQLite transaction per message to set a column that
        // already said 0 - thirty of them per page, for nothing.
        const wasRemoved = flags.removed.indexOf(msg.convId);
        if (fromSignal && fresh && isNews && wasRemoved >= 0) {
            root.store.setRemoved(msg.convId, false);
            // The local list has to agree: fold() reads `flags` rather than
            // asking the store a second time, so leaving the id in it would
            // fold the thread straight back to removed.
            flags.removed.splice(wasRemoved, 1);
        }

        root.fold(msg, flags);
        if (msg.convId === root.activeId) {
            root.refreshActive();
            // Still arriving, so the page is not finished. See pageSettleMs.
            if (root.loadingOlder) pageSettle.restart();
        }
        root.rebuild(flags.pins);
        // Same reasoning as the un-hide above: a page of backlog is not a
        // text that just arrived, so it does not get to raise one toast per
        // message. ControlPanel's handler already drops toasts for the
        // thread you are READING, which hid this in the common case - but
        // open A, then open B before A's page lands, and A's history toasted
        // itself at you a message at a time.
        if (fromSignal && fresh && isNews) root.messageArrived(msg);
    }

    // The ten-field struct, or something else entirely. Checked before
    // parsing rather than after, because a null payload throws on field 2.
    function usable(raw: var): bool {
        if (!raw || raw.length === undefined || raw.length < 8) return false;
        return raw[6] !== undefined && raw[6] !== null
            && raw[7] !== undefined && raw[7] !== null;
    }

    // One store transaction and one rebuild for the whole lot.
    //
    // The single-message path does a DB write, a full re-sort and a
    // re-render each time. Fifty of those back to back on the UI thread, at
    // the same moment the open animation is running, is the freeze you can
    // feel when the pane appears.
    //
    // Raises nothing: a refresh is not news. See ingestMessage.
    function ingestBatch(rawList: var): void {
        if (!rawList || rawList.length === 0) return;
        let parsed = [];
        for (const raw of rawList)
            if (root.usable(raw)) parsed.push(root.parseMessage(raw));
        if (parsed.length === 0) return;

        if (root.store) {
            root.store.putAll(parsed);
            // A refresh that runs just after a send brings the echo back in
            // the batch rather than as a signal.
            for (const m of parsed)
                if (m.outgoing)
                    root.store.resolvePending(m.convId, m.body, m.ts, m.id);
        }

        const flags = root.flagsFor();
        for (const m of parsed) {
            root.seen[m.id] = true;
            // Same "forever" rule as ingestMessage - a refresh must not
            // resurrect a blocked number's thread either.
            if (flags.blocked.indexOf(m.convId) >= 0) continue;
            root.fold(m, flags);
        }
        root.refreshActive();
        root.rebuild(flags.pins);
    }

    // One store read standing in for pinnedIds()/removedIds()/blockedIds()
    // called separately per message - ingestBatch folds up to fifty messages
    // in one pass, each potentially creating a new thread entry, and a
    // three-query lookup per message is twelve times what a refresh needs.
    function flagsFor(): var {
        return {
            pins: root.store ? root.store.pinnedIds() : [],
            removed: root.store ? root.store.removedIds() : [],
            blocked: root.store ? root.store.blockedIds() : []
        };
    }

    // Folds one parsed message into the thread map. No store write, no
    // rebuild, no signal - the callers above own those, which is what lets
    // the batch path do them once. `flags` is `flagsFor()`'s result, read
    // ONCE by the caller for the same reason. `undefined` is fine - see the
    // `pinned`/`removed`/`blocked` lines below, where a missing list reads
    // as "none of them", same as an empty one.
    function fold(msg: var, flags: var): void {
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
            // The raw number behind the thread, kept BESIDE the resolved
            // name because ThreadList.listed searches both. `title` is the
            // contact's name as soon as a vCard matched, so without this a
            // saved contact could not be found by their own number at all -
            // only unsaved ones, whose title happens to BE the number.
            // resolve() has always returned it; it was never copied out.
            number: newer || !prev ? (who.number || primary) : prev.number,
            hue: root.palette ? root.palette.hueFor(primary) : "#FF888888",
            addresses: newer || !prev ? msg.addresses : prev.addresses,
            isGroup: newer || !prev ? msg.addresses.length > 1 : prev.isGroup,
            preview: newer || !prev ? root.previewFor(msg) : prev.preview,
            ts: newer || !prev ? msg.ts : prev.ts,
            // Unread is ours, not the phone's, past this first sighting:
            // there is no markRead on the interface, so once we have decided
            // a thread is read the phone cannot argue.
            unread: prev ? prev.unread : !msg.read,
            // A thread's FIRST fold - after every rebuild and reboot, since
            // `threads` starts empty every time - used to hardcode false
            // here regardless of what the store actually held. Pins live in
            // MessageStore, not on the wire at all, so every pinned
            // conversation read as unpinned until something else happened to
            // call reloadFlags() (pinning a different thread, say) and
            // re-synced the whole map in one go - which is exactly the
            // "pins vanish after a rebuild, then all come back once I pin
            // one more" symptom. removed/blocked are the same class of
            // field, read the same way.
            pinned: prev ? prev.pinned : (flags && flags.pins ? flags.pins.indexOf(msg.convId) >= 0 : false),
            // removed is the one flag that ingestMessage can flip mid-fold
            // (see the setRemoved call just above the root.fold() call) - so
            // unlike pinned above, a fresh `flags` read wins over `prev`
            // when it disagrees, instead of always trusting the stale value.
            removed: flags && flags.removed ? flags.removed.indexOf(msg.convId) >= 0
                                             : (prev ? prev.removed : false),
            blocked: prev ? prev.blocked : (flags && flags.blocked ? flags.blocked.indexOf(msg.convId) >= 0 : false)
        };
    }

    // Re-resolves every thread's name, initials and colour.
    //
    // The 229 vCards are read asynchronously and the first conversations
    // almost always land before that finishes, so threads get built titled by
    // their phone numbers. Without this they keep those numbers until the
    // next message arrives in each - which for a quiet thread is never.
    function relabel(): void {
        for (const id in root.threads) {
            const t = root.threads[id];
            const primary = t.addresses && t.addresses.length > 0
                ? t.addresses[0] : "";
            const who = root.contacts ? root.contacts.resolve(primary)
                                      : { name: primary, initials: "" };
            t.title = who.name;
            t.initials = who.initials;
            // Same field as fold()'s, re-resolved for the same reason: the
            // vCards land after the first threads are built.
            t.number = who.number || primary;
            t.hue = root.palette ? root.palette.hueFor(primary) : t.hue;
        }
        root.rebuild();
    }

    // Re-reads pins, unread, removed and blocked out of the store. Cheap,
    // and called whenever something outside this object has changed one of
    // them - togglePin, removeConversation, blockConversation.
    function reloadFlags(): void {
        if (!root.store) { root.rebuild(); return; }
        const pins = root.store.pinnedIds();
        const unread = root.store.unreadIds();
        const removed = root.store.removedIds();
        const blocked = root.store.blockedIds();
        for (const id in root.threads) {
            root.threads[id].pinned = pins.indexOf(id) >= 0;
            root.threads[id].unread = unread.indexOf(id) >= 0
                || root.threads[id].unread;
            root.threads[id].removed = removed.indexOf(id) >= 0;
            root.threads[id].blocked = blocked.indexOf(id) >= 0;
        }
        root.rebuild(pins);
    }

    // Pinned first in pin order, then everything by recency. Pinned threads
    // stay in the list as well as the grid - see ThreadList.
    //
    // `pins` is optional and is pinnedIds() when omitted. Every caller that
    // has just read it hands it in instead: this runs once per ingested
    // message, and pinnedIds() was the one query the per-message path paid
    // twice. Only `undefined` means "did not look" - an empty array passed
    // in is an answer, and is used as one rather than triggering a re-read.
    function rebuild(pins: var): void {
        // A local, not a reassigned parameter: a typed QML parameter is not
        // a place to be writing to.
        const order = pins === undefined
            ? (root.store ? root.store.pinnedIds() : []) : pins;
        let out = [];
        for (const id in root.threads) out.push(root.threads[id]);
        out.sort((a, b) => {
            const pa = order.indexOf(a.convId), pb = order.indexOf(b.convId);
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
        root.activeMessages = root.store.messages(
            root.activeId, Math.max(root.pageLimit, root.store.pageSize), 0);
    }

    function openConversation(convId: string): void {
        root.activeId = convId;
        // Back to one page. A thread you had scrolled a long way into must
        // not reopen with four hundred bubbles in it.
        root.pageLimit = root.store ? root.store.pageSize : 30;
        // Not for the empty id. "No thread open" is a real state and is
        // reached deliberately - stepping out of a conversation that was
        // just removed goes through here - but it is not a conversation, and
        // writing it as one put a junk `conversations` row with convId ""
        // in the store for touch() and setUnread() to keep updating.
        if (root.store && convId) {
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
        // The phone second, and not yet. The arrow keys walk the sidebar and
        // every step opens a thread, so a request fired from here is a
        // request per keypress at a phone that answers in its own time. The
        // thread you stopped on is the only one you meant.
        //
        // Nothing to ask for when nothing is open: requestPage arms
        // `loadingOlder` BEFORE it checks activeId (deliberately - see its
        // comment), so firing it for the empty id left the pane claiming to
        // be loading a page for 1.2s with no request in flight.
        if (convId) openSettle.restart();
        else openSettle.stop();
    }

    Timer {
        id: openSettle
        interval: 180
        repeat: false
        onTriggered: root.requestPage(0, root.store ? root.store.pageSize : 30)
    }

    // start/end are INDEXES into the thread, newest first. The /sms object's
    // requestConversation takes a timestamp; this interface does not, and
    // this is the interface that answers.
    function requestPage(start: int, count: int): void {
        root.fetchCount += 1;
        root.lastStart = start;
        // Half-open: (6, 0, 0) returns nothing and (6, 0, 2) returns two, so
        // `end` is EXCLUSIVE. start + count - 1 was one message short of a
        // page, every page.
        root.lastEnd = start + count;
        const path = root.devPathFor(root.deviceId);
        // Armed before the guard, like the counters above: a request that
        // could not go out must not leave the guard stuck either, and a phone
        // that answers nothing at all is the case that wedged it shut.
        root.loadingOlder = true;
        pageSettle.restart();
        if (!root.transportEnabled || !root.connected || !root.activeId) return;
        pageProc.command = ["busctl", "--user", "call", "org.kde.kdeconnect",
            path, root.convIface, "requestConversation", "xii",
            root.activeId, String(start), String(root.lastEnd)];
        pageProc.running = true;
    }

    function fetchOlder(): void {
        if (root.loadingOlder) return;
        const page = root.store ? root.store.pageSize : 30;
        // Show what is already cached below the current window first - the
        // phone may well have sent these pages already - and grow from what
        // is really there, so the window stays within one page of the thread
        // rather than climbing every time the top is touched.
        root.pageLimit = Math.max(root.pageLimit,
                                  root.activeMessages.length) + page;
        root.refreshActive();
        // From how many the PHONE has given us. The length of what is on
        // screen is the wrong index twice over: capped at a page, and padded
        // with pending rows that do not exist on the phone at all.
        root.requestPage(root.store ? root.store.fetchedCount(root.activeId)
                                    : root.activeMessages.length, page);
    }

    // ---- sending ----

    // replyToConversation, not sendSms: the thread id is what we have, and
    // this is the call the conversations interface offers for it.
    //
    // There is no receipt. Nothing returns, and nothing confirms - the
    // message is only real once the phone echoes it back as a
    // conversationUpdated. Until then the bubble says so.
    // Guessed from the extension, since a staged local file (picker or
    // clipboard paste) carries no mime of its own - ConversationView only
    // ever treats an attachment as an image via this field.
    //
    // The fallback is NOT an image. It used to be "image/jpeg" for anything
    // unrecognised, and the picker is a plain `zenity --file-selection` with
    // no filter on it, so attaching a video, a PDF or a voice memo produced
    // a bubble claiming to be a photo, failing to decode, and showing the
    // "Photo / not sent" recess. An attachment whose type we cannot name is
    // an attachment, and the bubble says so.
    function mimeForPath(path: string): string {
        const s = String(path);
        const dot = s.lastIndexOf(".");
        const ext = dot < 0 ? "" : s.slice(dot + 1).toLowerCase();
        switch (ext) {
        case "png":  return "image/png";
        case "gif":  return "image/gif";
        case "webp": return "image/webp";
        case "bmp":  return "image/bmp";
        case "jpg":
        case "jpeg": return "image/jpeg";
        case "mp4":  return "video/mp4";
        case "webm": return "video/webm";
        case "3gp":  return "video/3gpp";
        case "mkv":  return "video/x-matroska";
        case "amr":  return "audio/amr";
        case "m4a":  return "audio/mp4";
        case "mp3":  return "audio/mpeg";
        case "ogg":  return "audio/ogg";
        case "opus": return "audio/opus";
        case "wav":  return "audio/wav";
        case "pdf":  return "application/pdf";
        }
        return "application/octet-stream";
    }

    function send(text: string, attachments: var): string {
        const pendingId = "pending-" + Date.now();
        const path = root.devPathFor(root.deviceId);
        if (!root.activeId) return pendingId;
        // An empty field is not a message. Enter on an empty compose box is
        // the commonest way to hit this, and a blank bubble that can never
        // be confirmed would sit in the thread forever.
        const hasAttachments = (attachments || []).length > 0;
        if (!String(text).trim() && !hasAttachments) return "";

        const atts = (attachments || []).map(a => String(a));
        let cmd = ["busctl", "--user", "call", "org.kde.kdeconnect",
                   path, root.convIface, "replyToConversation",
                   "xsav", root.activeId, text, String(atts.length)];
        for (const a of atts) cmd = cmd.concat(["s", a]);

        // Shown immediately, marked pending, carrying the ORIGINAL local file
        // - not the empty array this used to be stashed with. The phone's
        // own echo (`conversationUpdated`, a second or so later) carries
        // whatever its MMS send pass recompressed the photo down to, visibly
        // softer than what left this machine. MessageStore.resolvePending
        // copies this same attachments column onto that echo before dropping
        // the pending row, so the swap from "what I sent" to "what the
        // carrier mangled" never actually happens on screen.
        if (root.store) {
            root.store.putMessages(root.activeId, [{
                id: pendingId, convId: root.activeId, body: text,
                ts: Date.now(), outgoing: true,
                address: "", attachments: atts.map(a => ({
                    partId: -1, mime: root.mimeForPath(a), data: "",
                    uid: "", path: a
                }))
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
        const path = root.devPathFor(root.deviceId);
        if (!root.transportEnabled || !root.connected) return;
        attProc.command = ["busctl", "--user", "call", "org.kde.kdeconnect",
            path, root.convIface, "requestAttachmentFile",
            "xs", String(partId), uid];
        attProc.running = true;
    }

    // ---- transport ----

    function refresh(): void {
        // Counted before the guard: "we tried" is the thing worth asserting,
        // and an attempt that could not go out is exactly the case that used
        // to be lost silently.
        root.refreshCount += 1;
        const path = root.devPathFor(root.deviceId);
        if (!root.transportEnabled || !root.connected) return;
        listProc.command = ["busctl", "--user", "--json=short", "call",
            "org.kde.kdeconnect", path, root.convIface,
            "activeConversations"];
        listProc.running = true;
    }

    // The daemon's conversation list starts EMPTY, and nothing used to fill it.
    //
    // activeConversations() reads kdeconnectd's own cache; only a request to
    // the phone puts anything in it. kdeconnectd restarts on a reboot and on a
    // rebuild, so every first open after one read back `[[]]` and the pane
    // said "No conversations yet." next to a perfectly reachable phone - until
    // the Android SMS app was opened, which makes this exact call on its own
    // behalf and is why opening it "fixed" the panel.
    //
    // Nothing is returned. The threads arrive as conversationCreated signals,
    // which the monitor is already listening for, and are in the daemon's
    // cache for the next refresh. Only fired when the list came back empty:
    // the answer is one store write and one re-sort per thread, which is not
    // something to do on every open for a daemon that already has them.
    function primeThreads(): void {
        root.primeCount += 1;
        const path = root.devPathFor(root.deviceId);
        if (!root.transportEnabled || !root.connected) return;
        primeProc.command = ["busctl", "--user", "call", "org.kde.kdeconnect",
            path, root.convIface, "requestAllConversationThreads"];
        primeProc.running = true;
    }

    // What activeConversations() came back with. Split out of the Process so
    // the empty case - the whole bug above - is testable without a bus.
    function ingestList(rawList: var): void {
        if (!rawList || rawList.length === 0) { root.primeThreads(); return; }
        root.ingestBatch(rawList);
    }

    // When a page is considered finished, with no completion notice coming.
    //
    // conversationLoaded is NOT one. Measured on the bus, no shell involved:
    //
    //   requestConversation(6, 0, 29)  -> 29 updates, NO conversationLoaded
    //   requestConversation(6, 0, 199) -> 58 updates + conversationLoaded(6,58)
    //
    // The daemon raises it when the range EXHAUSTS the thread, not when the
    // request completes - so a page-sized request into a long thread never
    // completed as far as this model was concerned. `loadingOlder`, set by the
    // request that openConversation fires, was never cleared, and fetchOlder()
    // returned at its first line for the rest of the session: scrollback was
    // dead on precisely the threads long enough to need it.
    //
    // So the end of a page is inferred from it going quiet. Every message that
    // belongs to the open thread restarts this, which makes the window a gap
    // between messages rather than a deadline for the whole page - a
    // fifty-message answer over a slow link still counts as one.
    property int pageSettleMs: 1200

    // Whether a page is still being waited on. Read by fixtures; the view uses
    // loadingOlder.
    readonly property bool pageInFlight: pageSettle.running

    Timer {
        id: pageSettle
        interval: root.pageSettleMs
        repeat: false
        onTriggered: root.pageSettled()
    }

    function pageSettled(): void {
        root.loadingOlder = false;
        root.refreshActive();
    }

    // Coalesces a burst of conversationLoaded into one re-read.
    Timer {
        id: settle
        interval: 120
        repeat: false
        onTriggered: root.refreshActive()
    }

    Process { id: pageProc }
    Process { id: primeProc }
    Process { id: sendProc }
    Process { id: attProc }

    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(this.text).data[0];
                    root.ingestList(payload.map(e => e.data));
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
    // One bus signal, as `busctl --json=short monitor` prints it.
    //
    // Split out of the Process because the unwrap below is where the entire
    // signal side of this interface was being lost, and a SplitParser cannot
    // be fed a fixture.
    function handleSignal(ev: var): void {
        if (!ev || ev.type !== "signal" || ev.interface !== root.convIface) return;

        if (ev.member === "conversationCreated"
            || ev.member === "conversationUpdated") {
            const msg = root.structOf(ev.payload);
            if (msg) root.ingestMessage(msg, true);
        } else if (ev.member === "conversationLoaded") {
            // A completion notice carrying no content. A refresh produces one
            // of these PER THREAD - fifty in a burst - and re-reading the open
            // conversation out of SQLite fifty times is a visible stall.
            // Coalesced. It is also the only thing that clears the in-flight
            // guard, so missing it wedges fetchOlder() shut.
            root.loadingOlder = false;
            pageSettle.stop();
            settle.restart();
        } else if (ev.member === "conversationRemoved") {
            const id = String(root.structOf(ev.payload)[0]);
            delete root.threads[id];
            root.rebuild();
        } else if (ev.member === "attachmentReceived") {
            // (filePath, fileName), and fileName is the uniqueIdentifier the
            // attachment carries - the only thing tying the file on disk back
            // to the message that wants it.
            const d = root.structOf(ev.payload);
            if (root.store && d && d.length >= 2) {
                root.store.putAttachmentFile(String(d[1]), String(d[0]));
                root.attachmentReady(String(d[1]), String(d[0]));
            }
            root.refreshActive();
        }
    }

    // The ten fields out of a monitored payload.
    //
    // conversationCreated/Updated are `v`, and busctl prints a variant as
    // { type: "v", data: [ { type: "(isa(s)xiixixa(xsss))", data: [...] } ] }
    // - the struct is wrapped TWICE, once in the variant's one-element array
    // and once in its own {type,data}. The old code tested `v.data` on that
    // array, which is undefined on an Array, and fell through to the wrapper
    // itself: one field long, rejected by usable(), dropped in silence. No
    // toast ever fired and every page requested by fetchOlder() answered into
    // the void. Signals with a plain signature (conversationLoaded, xt) are
    // already the bare array at the first level.
    function structOf(payload: var): var {
        let v = payload ? payload.data : null;
        if (!v) return null;
        if (Array.isArray(v)) {
            if (v.length === 1 && v[0] && !Array.isArray(v[0])
                && v[0].data !== undefined)
                return v[0].data;
            return v;
        }
        return v.data !== undefined ? v.data : v;
    }

    Process {
        id: monitorProc
        // Gated on KNOWING the device, not on it being reachable. An idle
        // monitor on a sleeping phone costs nothing and is already in place
        // the moment the daemon emits something; waiting for reachability
        // would mean missing the first message after every wake.
        running: (root.active || root.listening)
                 && root.transportEnabled && root.deviceId !== ""
        command: ["busctl", "--user", "--json=short", "monitor",
                  "org.kde.kdeconnect"]
        stdout: SplitParser {
            onRead: line => {
                let ev;
                try { ev = JSON.parse(line); } catch (e) { return; }
                root.handleSignal(ev);
            }
        }
    }

    // Two different lifetimes, and the first version gave them one flag.
    //
    // Retention runs ONCE per shell: nothing about a 30-day window needs
    // noticing within the minute. But the conversation list has to be asked
    // for on EVERY open - share the guard and a panel opened before the
    // phone is awake says "No conversations yet." for the rest of the
    // session, because every later open returns early.
    property bool evicted: false
    property int refreshCount: 0
    property int evictCount: 0
    property int primeCount: 0

    onActiveChanged: {
        if (!active) return;
        if (!root.evicted) {
            root.evicted = true;
            root.evictCount += 1;
            if (root.store) root.store.evictStale();
        }
        root.refresh();
    }

    // The phone usually turns up AFTER the pane does.
    //
    // MobileModel finds out which device is reachable by shelling out to
    // kdeconnect-cli, a few hundred milliseconds behind the panel opening.
    // mod+m activates this immediately, so the refresh fired by
    // onActiveChanged hits `connected == false` and returns having asked
    // nothing. With no retry, opening Messages from a closed panel showed an
    // empty list next to a perfectly reachable phone.
    onConnectedChanged: if (root.connected && root.active) root.refresh()
}
