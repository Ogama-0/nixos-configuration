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

        if (bad.length > 0) { console.log("STORE_FAIL " + bad.join(" | ")); return; }
        console.log("STORE_OK");
    }
}
