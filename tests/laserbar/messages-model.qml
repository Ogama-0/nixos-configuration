import QtQuick
import Quickshell
import "components/panel/messages"

// MessagesModel, fed the payload captured in docs/kdeconnect-sms-payload.md.
//
// The arrays below are verbatim ConversationMessage structs off this machine,
// trimmed to five and with the bodies left as they arrived. They are the
// whole point of the fixture: the shape is not invented, so a change in KDE
// Connect that breaks the mapping breaks this.
//
//   (isa(s)xiixixa(xsss))
//    0 eventField  1 body  2 addresses  3 date(ms)  4 type(1 recv/2 sent)
//    5 read  6 threadID  7 uID  8 subID  9 attachments
//
// Logic fixture, not a render fixture:
//   scripts/qml-logic-test.sh tests/laserbar/messages-model.qml MODEL_OK
ShellRoot {
    id: root

    // Duck-typed stand-ins. MessagesModel only ever calls resolve() and
    // hueFor(), so a real ContactsModel (which would need 229 files on disk)
    // and a real MessageHue (which would need the theme) buy nothing here.
    QtObject {
        id: fakeContacts
        function resolve(number) {
            if (number === "+33766417775")
                return { name: "Benjamin Poussart", initials: "BP",
                         number: number, known: true };
            return { name: number, initials: "", number: number, known: false };
        }
    }

    QtObject {
        id: fakeHue
        function hueFor(number) { return "#FF27D796"; }
    }

    MessageStore {
        id: store
        dbName: "qs-messages-model-test"
    }

    MessagesModel {
        id: model
        contacts: fakeContacts
        palette: fakeHue
        store: store
        deviceId: "test-device"
        // Nothing may shell out during this fixture.
        transportEnabled: false
    }

    readonly property var captured: [
        // received, from an alphanumeric sender id
        [1, "[Uber] Votre code : 1358. Ne le divulguez jamais.",
         [["Uber"]], 1790539013048, 1, 1, 30, 243, 1, []],
        // sent, from a known contact's thread
        [1, "Qui pourrais m'aller genre ",
         [["+33766417775"]], 1792742983591, 2, 1, 29, 590, -1, []],
        // older message in that same thread, received
        [1, "ok à demain",
         [["+33766417775"]], 1792742900000, 1, 1, 29, 589, -1, []],
        // a group MMS with an attachment and an empty body
        [2, "", [["+33662843597"], ["+33616561744"]], 1792262331000, 1, 1, 6,
         10, 1, [[14, "audio/amr", "", "PART_1792262330991_Audio%20Mes1.amr"]]],
        // unread
        [1, "Ouffff", [["+33769223996"]], 1791294527488, 1, 0, 35, 408, 1, []]
    ]

    function byId(id) {
        return model.conversations.filter(c => c.convId === String(id))[0];
    }

    Component.onCompleted: {
        let bad = [];
        const check = (ok, why) => { if (!ok) bad.push(why); };

        store.init();
        store.wipe();

        for (const m of root.captured) model.ingestMessage(m);

        // One conversation per threadID, not one per message.
        check(model.conversations.length === 4,
              "expected 4 threads, got " + model.conversations.length);

        // --- direction ---
        const parsed = model.parseMessage(root.captured[1]);
        check(parsed.outgoing === true, "type 2 did not read as outgoing");
        check(model.parseMessage(root.captured[0]).outgoing === false,
              "type 1 did not read as incoming");
        check(parsed.id === "590", "uID is not the message id: " + parsed.id);
        check(parsed.convId === "29", "threadID is not the conv id: " + parsed.convId);
        check(parsed.ts === 1792742983591, "date did not survive as ms");

        // --- naming ---
        check(root.byId(29).title === "Benjamin Poussart",
              "a known contact was not resolved: " + root.byId(29).title);
        check(root.byId(30).title === "Uber",
              "an alphanumeric sender lost its name: " + root.byId(30).title);

        // --- groups ---
        check(root.byId(6).isGroup === true, "two addresses did not read as a group");
        check(root.byId(29).isGroup === false, "one address read as a group");

        // --- preview ---
        // The newest message in the thread, and a message with no body still
        // has to preview as something.
        check(root.byId(29).preview === "Qui pourrais m'aller genre ",
              "preview is not the newest body: " + root.byId(29).preview);
        check(String(root.byId(6).preview).length > 0,
              "an attachment-only message previewed as nothing");

        // --- unread ---
        check(root.byId(35).unread === true, "read=0 did not read as unread");
        check(root.byId(30).unread === false, "read=1 read as unread");

        // --- ordering: pinned first, then newest ---
        store.setPinned("6", true);
        model.reloadFlags();
        check(model.conversations[0].convId === "6",
              "pinned thread is not first: "
              + model.conversations.map(c => c.convId).join(","));
        const rest = model.conversations.slice(1);
        check(rest[0].convId === "29",
              "unpinned threads are not newest-first: "
              + rest.map(c => c.convId).join(","));

        // --- the cache is served before the phone answers ---
        model.openConversation("29");
        check(model.activeMessages.length === 2,
              "opening a thread did not serve the cache: "
              + model.activeMessages.length);
        check(model.activeMessages[0].id === "590",
              "cached messages are not newest-first");

        // --- fetchOlder is guarded ---
        // Without this a flick to the top of a thread fires one request per
        // frame at a phone that answers in its own time.
        model.loadingOlder = true;
        const before = model.fetchCount;
        model.fetchOlder();
        check(model.fetchCount === before,
              "fetchOlder fired while a page was already in flight");
        model.loadingOlder = false;
        model.fetchOlder();
        check(model.fetchCount === before + 1,
              "fetchOlder did not fire once the guard cleared");

        // --- idempotence ---
        for (const m of root.captured) model.ingestMessage(m);
        check(model.conversations.length === 4,
              "re-ingesting duplicated threads: " + model.conversations.length);
        model.openConversation("29");
        check(model.activeMessages.length === 2,
              "re-ingesting duplicated messages: " + model.activeMessages.length);

        if (bad.length > 0) { console.log("MODEL_FAIL " + bad.join(" | ")); return; }
        console.log("MODEL_OK");
    }
}
