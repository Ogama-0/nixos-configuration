import QtQuick
import Quickshell
import Quickshell.Io
import "components/panel/messages"

// ContactsModel, against vCards this fixture writes itself.
//
// Not the user's real ~/.local/share/kpeoplevcard set: that is 229 cards that
// change whenever the phone syncs, so an assertion against a name in it would
// start failing for reasons that have nothing to do with this code.
//
// The two Benjamin cases are the whole point of normalize(). KDE Connect hands
// back whatever string the SMS arrived with, and the contact card stores
// whatever the user typed - a French mobile reaches you as +33767248570 and
// sits in the address book as 076-724-8570. They are one person.
//
// Logic fixture, not a render fixture: run it with
//   scripts/qml-logic-test.sh tests/laserbar/messages-contacts.qml CONTACTS_OK
ShellRoot {
    id: root

    readonly property string dir: "/tmp/qs-messages-contacts-test"

    readonly property var cases: [
        { number: "076-724-8570", name: "Benjamin Poussart", initials: "BP", known: true },
        { number: "+33767248570", name: "Benjamin Poussart", initials: "BP", known: true },
        { number: "0760000001",   name: "Zoe",               initials: "Z",  known: true },
        { number: "32665",        name: "32665",             initials: "",   known: false },
        { number: "",             name: "",                  initials: "",   known: false }
    ]

    ContactsModel {
        id: contacts
        onReadyChanged: if (ready) root.check()
    }

    function check(): void {
        let bad = [];
        for (const c of root.cases) {
            const got = contacts.resolve(c.number);
            if (got.name !== c.name || got.initials !== c.initials
                || got.known !== c.known || got.number !== c.number) {
                bad.push(c.number + " -> name=" + got.name
                    + " initials=" + got.initials + " known=" + got.known
                    + " number=" + got.number);
            }
        }
        if (bad.length > 0) {
            console.log("CONTACTS_FAIL " + bad.join(" | "));
            return;
        }
        // Last, and only once everything above held: the runner stops the
        // process the moment it sees this line.
        console.log("CONTACTS_OK");
    }

    // A single-word FN must yield one initial, not crash reaching for a
    // surname that is not there - hence Zoe with no last name.
    Process {
        id: seed
        running: true
        command: ["sh", "-c",
            "set -e; rm -rf " + root.dir + "; mkdir -p " + root.dir + "; "
            + "printf 'BEGIN:VCARD\\nVERSION:2.1\\nN:Poussart;Benjamin;;;\\n"
            + "FN:Benjamin Poussart\\nTEL;CELL:076-724-8570\\nEND:VCARD\\n' > "
            + root.dir + "/benjamin.vcf; "
            + "printf 'BEGIN:VCARD\\nVERSION:2.1\\nN:;Zoe;;;\\nFN:Zoe\\n"
            + "TEL;CELL:+33 7 60 00 00 01\\nEND:VCARD\\n' > "
            + root.dir + "/zoe.vcf"]
        onExited: exitCode => {
            if (exitCode !== 0) { console.log("CONTACTS_FAIL could not seed vcards"); return; }
            contacts.loadFrom(root.dir);
        }
    }
}
