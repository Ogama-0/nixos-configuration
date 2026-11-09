import QtQuick
import Quickshell
import "components/panel/messages"

// MessageStore, against a throwaway database.
//
// Never the real one. The store is a cache of the user's actual texts, and a
// fixture that wrote test rows into it would both corrupt their history and
// start passing or failing depending on who had messaged them that week.
//
// Logic fixture, not a render fixture: run it with
//   scripts/qml-logic-test.sh tests/laserbar/messages-store.qml STORE_OK
ShellRoot {
    id: root

    readonly property int day: 24 * 60 * 60 * 1000
    readonly property real now: Date.now()

    MessageStore {
        id: store
        dbName: "qs-messages-store-test"
    }

    function msg(id, conv, body, ts, outgoing): var {
        return { id: id, convId: conv, body: body, ts: ts,
                 outgoing: outgoing === true, address: "+33600000001",
                 attachments: [] };
    }

    Component.onCompleted: {
        let bad = [];
        const check = (ok, why) => { if (!ok) bad.push(why); };

        store.init();
        store.wipe();  // a previous run's rows are not this run's fixture

        const A = "conv-a";
        const B = "conv-b";

        // --- idempotent writes -------------------------------------------
        // The same message arrives again every time a thread is reopened and
        // on every conversationUpdated. Twice must not mean two bubbles.
        store.putMessages(A, [root.msg("m1", A, "hello world", root.now - 3000, false)]);
        store.putMessages(A, [root.msg("m1", A, "hello world", root.now - 3000, false)]);
        check(store.messages(A, 30, 0).length === 1,
              "duplicate put created " + store.messages(A, 30, 0).length + " rows");

        // --- ordering and limit -------------------------------------------
        store.putMessages(A, [
            root.msg("m2", A, "second", root.now - 2000, true),
            root.msg("m3", A, "third",  root.now - 1000, false)
        ]);
        const newest = store.messages(A, 30, 0);
        check(newest.length === 3, "expected 3 messages, got " + newest.length);
        check(newest.length === 3 && newest[0].id === "m3",
              "not newest-first: " + newest.map(m => m.id).join(","));
        check(store.messages(A, 2, 0).length === 2, "limit 2 ignored");

        // --- paging backwards ----------------------------------------------
        // What fetchOlder() stands on: everything strictly older than the
        // oldest row already shown.
        const older = store.messages(A, 30, root.now - 2000);
        check(older.length === 1 && older[0].id === "m1",
              "beforeTs returned " + older.map(m => m.id).join(","));

        // --- nothing cached --------------------------------------------------
        check(store.oldestTimestamp("conv-never-seen") === 0,
              "unknown conversation did not report 0");

        // --- retention --------------------------------------------------------
        store.putMessages(B, [root.msg("m4", B, "keep me", root.now - 1000, false)]);
        store.touch(A, root.now - 31 * root.day);
        store.touch(B, root.now - 1 * root.day);
        const evicted = store.evictStale();
        check(evicted >= 1, "evictStale reported " + evicted);
        check(store.messages(B, 30, 0).length === 1, "evicted a fresh conversation");

        // Review Focus 2: an evicted thread must be distinguishable from a
        // thread with nothing older, or the pane shows a permanent blank
        // instead of re-fetching.
        check(store.messages(A, 30, 0).length === 0,
              "evicted conversation still has messages");
        check(store.oldestTimestamp(A) === 0,
              "evicted conversation did not report 0 as oldest");

        // --- search -----------------------------------------------------------
        store.putMessages(B, [root.msg("m5", B, "hello world again", root.now, false)]);
        check(store.search("world", 20).length >= 1, "search missed a plain word");
        check(store.search("nothingmatchesthis", 20).length === 0,
              "search invented a result");

        // Review Focus 4, the half that actually discriminates. A bare OR is
        // an FTS5 operator and a syntax error on its own; sanitised, it is
        // the word "OR" and matches this body. Asserting only "did not throw"
        // passes just as happily against a search() that throws on every
        // operator and swallows it - which is a search box that silently
        // returns nothing for half of what you type.
        store.putMessages(B, [root.msg("m6", B, "report OR nothing", root.now, false)]);
        check(store.search("OR", 20).length >= 1,
              "a literal OR found nothing - the query is reaching FTS5 unsanitised");
        check(store.search("hello world", 20).length >= 1,
              "a two-word phrase found nothing");

        // The rest of Review Focus 4: whatever else a person types, the panel
        // must not raise.
        for (const q of ['"', '*', 'OR', '-', 'a OR', '""', '* *']) {
            let res;
            try { res = store.search(q, 20); }
            catch (e) { bad.push("search(" + q + ") threw: " + e); continue; }
            if (!Array.isArray(res)) bad.push("search(" + q + ") returned a non-array");
        }

        // --- pins and unread ---------------------------------------------------
        store.setPinned(A, true);
        store.setPinned(B, false);
        check(store.pinnedIds().indexOf(A) >= 0, "pin did not round-trip");
        check(store.pinnedIds().indexOf(B) < 0, "unpinned conversation came back pinned");
        store.setPinned(A, false);
        check(store.pinnedIds().indexOf(A) < 0, "unpin did not round-trip");

        store.setUnread(B, true);
        check(store.unreadIds().indexOf(B) >= 0, "unread did not round-trip");
        store.setUnread(B, false);
        check(store.unreadIds().indexOf(B) < 0, "read did not round-trip");

        // --- pending rows are replaced by the echo, not joined by it ---------
        //
        // There is no delivery receipt: send() writes a pending-<ts> row so
        // the bubble appears at once, and the phone echoes the same text back
        // a second later carrying its real uID. Nothing used to remove the
        // pending row, so every message this panel sent ended up on screen
        // TWICE - 20 of the 99 rows in the real cache were orphaned pendings.
        const C = "conv-c";
        const sentAt = root.now - 5000;
        store.putMessages(C, [root.msg("pending-" + sentAt, C, "bonjour a tous",
                                       sentAt, true)]);
        store.putMessages(C, [root.msg("660", C, "bonjour a tous",
                                       sentAt + 1061, true)]);
        store.resolvePending(C, "bonjour a tous", sentAt + 1061, "660");
        const after = store.messages(C, 30, 0);
        check(after.length === 1,
              "the echo did not replace the pending row: "
              + after.map(m => m.id).join(","));
        check(after.length === 1 && after[0].id === "660",
              "the wrong row survived: " + after.map(m => m.id).join(","));
        // ...and the search index must not keep the copy either, or one
        // sent message is two hits.
        check(store.search("bonjour a tous", 20).length === 1,
              "the pending row stayed in the FTS index: "
              + store.search("bonjour a tous", 20).length);

        // A pending row nobody echoed is NOT swept. "Sent" forever is the
        // honest state when the phone never confirmed - see docs.
        store.putMessages(C, [root.msg("pending-" + root.now, C, "never echoed",
                                       root.now, true)]);
        store.resolvePending(C, "something else", root.now, "no-such-echo");
        check(store.messages(C, 30, 0).length === 2,
              "resolvePending swept an unconfirmed message");

        // --- resolvePending carries the ORIGINAL attachment onto the echo ---
        //
        // The phone's own echo for a sent photo carries whatever its MMS
        // send pass recompressed it down to - visibly softer than what left
        // this machine. The pending row is the only place the original file
        // path survives; resolvePending has to copy it onto the echo before
        // the pending row (and that path with it) is deleted.
        const D = "conv-d";
        const photoAt = root.now - 4000;
        store.putMessages(D, [{
            id: "pending-" + photoAt, convId: D, body: "", ts: photoAt,
            outgoing: true, address: "",
            attachments: [{ partId: -1, mime: "image/png", data: "",
                            uid: "", path: "/tmp/original.png" }]
        }]);
        store.putMessages(D, [{
            id: "661", convId: D, body: "", ts: photoAt + 900,
            outgoing: true, address: "",
            attachments: [{ partId: 3, mime: "image/jpeg",
                            data: "dGlueQ==", uid: "u1", path: "" }]
        }]);
        store.resolvePending(D, "", photoAt + 900, "661");
        const photoAfter = store.messages(D, 30, 0);
        check(photoAfter.length === 1 && photoAfter[0].id === "661",
              "the photo echo did not replace the pending row: "
              + photoAfter.map(m => m.id).join(","));
        check(photoAfter.length === 1
              && photoAfter[0].attachments.length === 1
              && photoAfter[0].attachments[0].path === "/tmp/original.png",
              "the surviving row lost the original attachment: "
              + JSON.stringify(photoAfter[0] && photoAfter[0].attachments));
        // ...and kept everything the PHONE said about it. The first version
        // of this assigned the pending row's whole attachments column over
        // the echo's, which threw away partId, mime, uid and the inline
        // bytes - and `uid` is the only handle requestAttachmentFile has, so
        // a staged clipboard paste (/tmp, gone after a reboot) left the
        // photo unrenderable AND unfetchable for good.
        const pa = photoAfter[0].attachments[0];
        check(pa.uid === "u1" && pa.partId === 3 && pa.mime === "image/jpeg"
              && pa.data === "dGlueQ==",
              "the merge overwrote what the phone announced: " + JSON.stringify(pa));

        // --- one echo resolves ONE pending row ------------------------------
        //
        // Two uncaptioned photos sent inside the window are both body "", so
        // the pending lookup matches both. Taking all of them meant the first
        // echo deleted the second message's pending row as well - it vanished
        // from the thread until its own echo arrived - and wrote the second
        // photo onto the FIRST echo on the way past.
        const E = "conv-e";
        const pOne = root.now - 9000, pTwo = root.now - 8000;
        store.putMessages(E, [{
            id: "pending-" + pOne, convId: E, body: "", ts: pOne,
            outgoing: true, address: "",
            attachments: [{ partId: -1, mime: "image/png", data: "",
                            uid: "", path: "/tmp/first.png" }]
        }]);
        store.putMessages(E, [{
            id: "pending-" + pTwo, convId: E, body: "", ts: pTwo,
            outgoing: true, address: "",
            attachments: [{ partId: -1, mime: "image/png", data: "",
                            uid: "", path: "/tmp/second.png" }]
        }]);
        store.putMessages(E, [{
            id: "770", convId: E, body: "", ts: pOne + 400, outgoing: true,
            address: "",
            attachments: [{ partId: 1, mime: "image/jpeg", data: "",
                            uid: "e1", path: "" }]
        }]);
        store.resolvePending(E, "", pOne + 400, "770");
        const twoAfter = store.messages(E, 30, 0);
        check(twoAfter.length === 2,
              "one echo swept both pending photos: "
              + twoAfter.map(m => m.id).join(","));
        const echoed = twoAfter.filter(m => m.id === "770")[0];
        check(echoed && echoed.attachments[0].path === "/tmp/first.png",
              "the echo took the WRONG photo: "
              + JSON.stringify(echoed && echoed.attachments));
        const stillPending = twoAfter.filter(m => m.id !== "770")[0];
        check(stillPending && stillPending.id === "pending-" + pTwo,
              "the second photo's pending row did not survive: "
              + twoAfter.map(m => m.id).join(","));

        // --- how many of the newest the phone has given us -------------------
        //
        // The index requestConversation() pages from. It cannot be the length
        // of what is on screen: that is capped at one page and inflated by
        // local pending rows, so asking for "the next 30 after what I have"
        // re-requested a page we already held and never reached the older
        // ones.
        check(store.fetchedCount(C) === 1,
              "fetchedCount counted pending rows: " + store.fetchedCount(C));
        check(store.fetchedCount("conv-never-seen") === 0,
              "fetchedCount invented messages for an unknown thread");

        if (bad.length > 0) { console.log("STORE_FAIL " + bad.join(" | ")); return; }
        console.log("STORE_OK");
    }
}
