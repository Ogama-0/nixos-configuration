import QtQuick
import Quickshell
import "components/panel/messages"

// Walking the sidebar with the keyboard.
//
// The key BINDINGS cannot be asserted here - nothing in this harness
// synthesises a key press - so what this covers is the thing underneath
// them: which row an arrow lands on, and that moving the selection is the
// same act as opening the thread. The bindings themselves are four lines
// each and are checked by `scripts/laserbar-preview.sh real` loading the
// shell without a QML error.
//
// Logic fixture, not a render fixture:
//   scripts/qml-logic-test.sh tests/laserbar/messages-nav.qml NAV_OK
ShellRoot {
    id: root

    // Newest first is how ThreadList sorts them, so this is also the order
    // the arrows should walk.
    readonly property var threads: [
        { convId: "51", title: "Benjamin", preview: "Mdr je capte",
          ts: 1793050957099, unread: false, pinned: false, initials: "B",
          hue: "#FF27D796", isGroup: false, addresses: ["+33766417775"] },
        { convId: "13", title: "Maman", preview: "Coucou",
          ts: 1793040000000, unread: true, pinned: false, initials: "M",
          hue: "#FF27D796", isGroup: false, addresses: ["+33611111111"] },
        { convId: "30", title: "Uber", preview: "Votre code",
          ts: 1790539013048, unread: false, pinned: false, initials: "",
          hue: "#FF27D796", isGroup: false, addresses: ["Uber"] }
    ]

    property var picked: []

    ThreadList {
        id: list
        width: 340
        height: 600
        conversations: root.threads
        // What the pane does: the selection IS the open thread, so the
        // fixture has to close that loop too or step() walks in place.
        activeId: ""
        onConversationPicked: convId => {
            root.picked.push(convId);
            list.activeId = convId;
        }
    }

    // arrowsBorrowed() is pure - no core, no audio, no thread needed to call
    // it - so an unconfigured pane is enough.
    MessagesPane {
        id: pane
    }

    Component.onCompleted: {
        let bad = [];
        const check = (ok, why) => { if (!ok) bad.push(why); };

        check(list.selectedIndex === -1,
              "nothing is open and the selection is not empty: "
              + list.selectedIndex);

        // A first press with nothing selected must land somewhere, whichever
        // direction it was - a key that does nothing reads as a dead panel.
        list.step(-1);
        check(list.activeId === "51",
              "the first keypress did not select the newest thread: "
              + list.activeId);

        list.step(1);
        check(list.activeId === "13", "down did not advance: " + list.activeId);
        check(list.selectedIndex === 1,
              "selectedIndex disagrees with activeId: " + list.selectedIndex);

        list.step(1);
        check(list.activeId === "30", "down did not advance twice: " + list.activeId);

        // Clamped at both ends. Wrapping would mean that holding Down walks
        // off the bottom of the inbox and back round to the top of it.
        list.step(1);
        check(list.activeId === "30", "down ran off the end: " + list.activeId);
        check(root.picked.length === 3,
              "a step that changed nothing still opened a thread: "
              + root.picked.join(","));

        list.step(-1);
        list.step(-1);
        check(list.activeId === "51", "up did not walk back: " + list.activeId);
        list.step(-1);
        check(list.activeId === "51", "up ran off the top: " + list.activeId);

        // The arrows walk what is ON SCREEN, not the whole inbox: with a
        // query typed, Down must step through the matches.
        list.query = "uber";
        check(list.listed.length === 1,
              "the filter did not narrow the list: " + list.listed.length);
        list.activeId = "";
        list.step(1);
        check(list.activeId === "30",
              "a filtered list stepped onto a hidden thread: " + list.activeId);

        // An empty list is not a crash.
        list.query = "nothingmatchesthis";
        const before = root.picked.length;
        list.step(1);
        list.step(-1);
        check(root.picked.length === before,
              "stepping an empty list opened something");

        if (bad.length > 0) { console.log("NAV_FAIL " + bad.join(" | ")); return; }

        // arrowsBorrowed() is the pure decision behind the left/right skip:
        // whether a voice note is playing, and whether the compose field -
        // where the left arrow is the text cursor, not a shortcut - has the
        // keyboard. No key press is synthesised; the fixture calls the
        // function directly, same as it calls list.step() above.
        check(pane.arrowsBorrowed("a", false) === true,
              "playing, hands off the compose field: the arrows are the skips");
        check(pane.arrowsBorrowed("a", true) === false,
              "the caret key would have moved the playhead mid-draft");
        check(pane.arrowsBorrowed("", false) === false,
              "nothing is playing and the arrows did not come back");
        check(pane.arrowsBorrowed("", true) === false,
              "nothing is playing and the compose field should not matter either");

        if (bad.length > 0) { console.log("NAV_FAIL " + bad.join(" | ")); return; }
        console.log("NAV_OK");
    }
}
