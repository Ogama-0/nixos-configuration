import QtQuick
import Quickshell
import "components/panel/messages"

// Sending, and the honesty of what the bubble claims afterwards.
//
// replyToConversation returns nothing and confirms nothing. There is no
// delivery receipt anywhere on the interface, so the only truthful states
// are "we handed it over" and "the phone has echoed it back". Anything that
// promotes a message to delivered on a timer is lying to you about a text
// that may never have left the building.
//
// Logic fixture:
//   scripts/qml-logic-test.sh tests/laserbar/messages-compose.qml COMPOSE_OK
ShellRoot {
    id: root

    QtObject {
        id: fakeContacts
        function resolve(number) {
            return { name: number, initials: "", number: number, known: false };
        }
    }
    QtObject {
        id: fakeHue
        function hueFor(number) { return "#FF27D796"; }
    }

    MessageStore { id: store; dbName: "qs-messages-compose-test" }

    MessagesModel {
        id: model
        contacts: fakeContacts
        palette: fakeHue
        store: store
        transportEnabled: false
    }

    MessageStore { id: awayStore; dbName: "qs-messages-away-test" }

    // Paired, known, and not on the network.
    MessagesModel {
        id: away
        contacts: fakeContacts
        palette: fakeHue
        store: awayStore
        deviceId: "test-device"
        reachable: false
        transportEnabled: false
    }

    Component.onCompleted: {
        let bad = [];
        const check = (ok, why) => { if (!ok) bad.push(why); };

        store.init();
        store.wipe();
        awayStore.init();
        awayStore.wipe();

        // A thread to send into.
        model.ingestMessage([1, "ok à demain", [["+33766417775"]],
                             1792742900000, 1, 1, 29, 589, -1, []]);
        model.openConversation("29");

        // --- Review Focus 3: sending with no phone must not lose the text ---
        // deviceId is empty, so `connected` is false: this is the "phone is
        // asleep / off the network" case, and the one where a panel that
        // dropped the message silently would be at its worst.
        check(model.connected === false, "fixture is not in the disconnected case");

        const before = model.activeMessages.length;
        let pendingId = "";
        try {
            pendingId = model.send("Je suis en route", []);
        } catch (e) {
            bad.push("send() threw while disconnected: " + e);
        }

        check(pendingId !== "", "send() returned no id");
        check(model.activeMessages.length === before + 1,
              "the message did not appear at all: "
              + model.activeMessages.length + " vs " + before);

        const shown = model.activeMessages[0];
        check(shown && shown.body === "Je suis en route",
              "the newest bubble is not the text that was typed");
        check(shown && shown.outgoing === true, "a sent message read as incoming");

        // It survives a reload, so the draft is not lost to a restart.
        model.openConversation("29");
        check(model.activeMessages.filter(m => m.body === "Je suis en route").length === 1,
              "the pending message did not survive being re-read from the store");

        // --- and it must NOT claim delivery ---
        const stored = model.activeMessages.filter(m => m.id === pendingId)[0];
        check(stored !== undefined, "the pending message lost its id");
        check(!stored || stored.delivered !== true,
              "an unconfirmed message claimed Delivered");

        // --- the phone echoing it back is what confirms it ---
        // Same body, now with a real uID off the wire.
        model.ingestMessage([1, "Je suis en route", [["+33766417775"]],
                             Date.now(), 2, 1, 29, 591, -1, []]);
        model.openConversation("29");
        const echoed = model.activeMessages.filter(m => m.id === "591")[0];
        check(echoed !== undefined, "the echo did not land");
        check(echoed && echoed.outgoing === true, "the echo read as incoming");

        // --- empty sends are not messages ---
        const n = model.activeMessages.length;
        model.send("", []);
        model.openConversation("29");
        check(model.activeMessages.length === n,
              "an empty send created a bubble");

        // --- a paired phone that has wandered off ---
        //
        // kdeconnect-cli -a lists only REACHABLE devices, so a phone that is
        // asleep or off the wifi reports nothing even though it is paired.
        // That must not take the cache with it: everything already
        // downloaded is still readable, and the reason it cannot be added to
        // is "the phone is away", not "pair a phone".
        away.ingestMessage([1, "déjà lu", [["+33766417775"]],
                            1792742900000, 1, 1, 44, 700, -1, []]);
        away.openConversation("44");
        check(away.activeMessages.length === 1,
              "a paired-but-unreachable device lost its cache: "
              + away.activeMessages.length);
        check(away.conversations.length === 1,
              "a paired-but-unreachable device lost its conversation list");
        // Knowing which device we are is what makes the cache and the
        // contacts reachable at all.
        check(away.deviceId === "test-device",
              "the paired device id did not survive unreachability");
        // But it is NOT connected, so nothing may be sent and nothing may
        // shell out at a phone that is not there.
        check(away.connected === false,
              "an unreachable device reported itself connected");

        if (bad.length > 0) { console.log("COMPOSE_FAIL " + bad.join(" | ")); return; }
        console.log("COMPOSE_OK");
    }
}
