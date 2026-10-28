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

    // A contacts stub that only starts knowing the name partway through,
    // standing in for the vCard read finishing after the first messages.
    QtObject {
        id: lateContacts
        property bool known: false
        function resolve(number) {
            if (known && number === "+33611111111")
                return { name: "Late Arrival", initials: "LA",
                         number: number, known: true };
            return { name: number, initials: "", number: number, known: false };
        }
    }

    MessageStore { id: lateStore; dbName: "qs-messages-model-late-test" }
    MessageStore { id: arriveStore; dbName: "qs-messages-model-arrive-test" }

    // Known phone, not yet reachable - the state mod+m opens into.
    MessagesModel {
        id: arrives
        contacts: fakeContacts
        palette: fakeHue
        store: arriveStore
        deviceId: "test-device"
        reachable: false
        transportEnabled: false
    }

    MessageStore { id: batchStore; dbName: "qs-messages-model-batch-test" }
    MessageStore { id: oneStore; dbName: "qs-messages-model-one-test" }

    MessagesModel {
        id: batchModel
        contacts: fakeContacts
        palette: fakeHue
        store: batchStore
        transportEnabled: false
    }

    MessagesModel {
        id: oneByOne
        contacts: fakeContacts
        palette: fakeHue
        store: oneStore
        transportEnabled: false
    }

    MessagesModel {
        id: lateModel
        contacts: lateContacts
        palette: fakeHue
        store: lateStore
        transportEnabled: false
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
        lateStore.init();
        lateStore.wipe();
        batchStore.init();
        batchStore.wipe();
        arriveStore.init();
        arriveStore.wipe();
        oneStore.init();
        oneStore.wipe();

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

        // --- a bulk refresh is not news ---
        //
        // Opening the pane re-reads all 50 conversations off the phone and
        // folds them in. Every one of those used to raise messageArrived,
        // so the panel toasted the entire inbox at you - texts you had read
        // days ago, every single time you opened it.
        //
        // A signal means something happened. A refresh means catching up.
        let heard = 0;
        batchModel.messageArrived.connect(() => heard += 1);

        batchModel.ingestBatch(root.captured);
        check(heard === 0, "a bulk refresh raised " + heard + " arrivals");
        check(batchModel.conversations.length === 4,
              "ingestBatch built the wrong list: "
              + batchModel.conversations.length);

        // A message we already hold is not news, even arriving as a signal.
        // The daemon re-emits conversationCreated for existing threads while
        // a refresh is in flight, so "did it come off the wire" is not
        // enough on its own - it has to be a message we have not seen.
        batchModel.ingestMessage(root.captured[0], true);
        check(heard === 0,
              "a message already in the list toasted again: " + heard);

        // ...and one off the wire still is news.
        batchModel.ingestMessage([1, "nouveau", [["+33700000000"]],
                                  Date.now(), 1, 0, 99, 999, -1, []], true);
        check(heard === 1, "a signalled message did not raise an arrival");

        // Same result either way - the batch path must not be a second,
        // subtly different parser.
        for (const m of root.captured) oneByOne.ingestMessage(m, false);
        check(oneByOne.conversations.length === batchModel.conversations.length - 1,
              "batch and single ingest disagree: "
              + oneByOne.conversations.length + " vs "
              + (batchModel.conversations.length - 1));

        // --- refresh happens on every open, eviction only once ---
        //
        // These were one statement guarded by one flag, so the conversation
        // list was requested exactly once per shell lifetime. Open the panel
        // before the phone is awake and it said "No conversations yet."
        // forever - every later open returned early.
        const r0 = lateModel.refreshCount;
        lateModel.active = true;
        check(lateModel.refreshCount === r0 + 1, "first open did not refresh");
        lateModel.active = false;
        lateModel.active = true;
        check(lateModel.refreshCount === r0 + 2,
              "a second open did not refresh: " + lateModel.refreshCount);
        check(lateModel.evictCount === 1,
              "eviction ran more than once: " + lateModel.evictCount);
        lateModel.active = false;

        // --- the phone that arrives late ---
        //
        // MobileModel learns which phone is reachable by shelling out to
        // kdeconnect-cli, which takes a few hundred milliseconds. mod+m
        // activates the pane immediately, so `connected` is still false when
        // onActiveChanged fires and refresh() returns early. Nothing used to
        // retry, so opening Messages from a closed panel showed "No
        // conversations yet." every single time while a perfectly reachable
        // phone sat there.
        const a0 = arrives.refreshCount;
        arrives.active = true;
        check(arrives.refreshCount === a0 + 1, "activating did not attempt a refresh");
        // Still unreachable, so that attempt could not have asked anything.
        check(arrives.connected === false, "fixture started out connected");

        arrives.reachable = true;
        check(arrives.refreshCount === a0 + 2,
              "the phone becoming reachable did not re-attempt the refresh");

        // And it must not re-ask on every unrelated change.
        arrives.reachable = true;
        check(arrives.refreshCount === a0 + 2,
              "a no-op reachability change re-asked: " + arrives.refreshCount);
        arrives.active = false;

        // --- names that arrive late ---
        // The 229 vCards are read asynchronously, and the first
        // conversations usually land before that finishes. Without a relabel
        // every thread keeps whatever it was built with - its phone number -
        // until the next message arrives, which for a quiet thread is never.
        lateContacts.known = false;
        lateModel.ingestMessage([1, "salut", [["+33611111111"]],
                                 1792742983591, 1, 1, 77, 900, -1, []]);
        check(lateModel.conversations[0].title === "+33611111111",
              "unresolved thread should be titled by its number, got "
              + lateModel.conversations[0].title);
        lateContacts.known = true;
        lateModel.relabel();
        check(lateModel.conversations[0].title === "Late Arrival",
              "relabel did not rename the thread: "
              + lateModel.conversations[0].title);
        check(lateModel.conversations[0].initials === "LA",
              "relabel did not update the initials");

        if (bad.length > 0) { console.log("MODEL_FAIL " + bad.join(" | ")); return; }
        console.log("MODEL_OK");
    }
}
