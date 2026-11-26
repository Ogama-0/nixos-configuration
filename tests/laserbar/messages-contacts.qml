import QtQuick
import Quickshell
import Quickshell.Io
import "panel/messagepanel"

// ContactsModel, against vCards this fixture writes itself.
//
// Not the user's real ~/.local/share/contacts/rustical set: that changes
// whenever the address book is edited, so an assertion against a name in it
// would start failing for reasons that have nothing to do with this code.
//
// The two Benjamin cases are the whole point of normalize(). An SMS hands
// back whatever string the number arrived with, and the contact card stores
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
        { number: "",             name: "",                  initials: "",   known: false },
        // No card for this one either, but it IS a full +33 mobile, so the
        // fallback groups it like a dial pad rather than printing one long
        // run of digits.
        { number: "+33611223344", name: "+33 6 11 22 33 44", initials: "",   known: false },
        // Alphanumeric sender IDs. Real traffic on this phone is full of them
        // - Uber, SIGNAL, "imagine R", LBPCF - and they contain NO DIGITS, so
        // a normaliser that strips to digits folds every one of them onto the
        // empty key: one contact, one colour, for the whole of your 2FA.
        { number: "Uber",         name: "Uber",              initials: "",   known: false },
        { number: "SIGNAL",       name: "SIGNAL",            initials: "",   known: false },
        { number: "imagine R",    name: "imagine R",         initials: "",   known: false },
        // The 2.1 cards the phone actually exports. Thirty of the 229 here
        // spell the name as FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE and
        // write it as =XX bytes - which is every contact whose name carries
        // an accent or an emoji. A parser that only knows "FN:" drops all
        // thirty, and those are precisely the threads that showed a bare
        // number next to a KDE notification that had the name.
        { number: "+522291085974", name: "Samüel Marines", initials: "SM", known: true },
        // ...and a value long enough that the exporter broke it with a QP
        // soft line break: a trailing "=" means "continued on the next
        // line", not "an equals sign".
        { number: "0611112222",   name: "Léonie❤️",         initials: "L",  known: true }
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
        // The collision itself, not just the rendering: two different sender
        // IDs must not normalise to the same key.
        const keys = ["Uber", "SIGNAL", "imagine R", "LBPCF"].map(n => contacts.normalize(n));
        if (new Set(keys).size !== keys.length)
            bad.push("sender IDs collided: " + JSON.stringify(keys));
        if (keys.indexOf("") >= 0)
            bad.push("a sender ID normalised to the empty key");

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
            + root.dir + "/zoe.vcf; "
            // Verbatim shape of a real quoted-printable card, including the
            // structured N: line that is also encoded and must not be
            // mistaken for the display name.
            + "printf 'BEGIN:VCARD\\nVERSION:2.1\\n"
            + "N;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=4D=61=72=69=6E=65=73;=53=61=6D=C3=BC=65=6C;;;\\n"
            + "FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=53=61=6D=C3=BC=65=6C=20=4D=61=72=69=6E=65=73\\n"
            + "TEL;CELL:+522291085974\\nEND:VCARD\\n' > "
            + root.dir + "/samuel.vcf; "
            // No trailing newline on this one either - the real files have
            // none, so `cat` over the glob joins END:VCARD to the next
            // BEGIN:VCARD on one line.
            + "printf 'BEGIN:VCARD\\nVERSION:2.1\\n"
            + "FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=4C=C3=A9=6F=6E=\\n"
            + "=69=65=E2=9D=A4=EF=B8=8F\\nTEL;PREF:0611112222\\nEND:VCARD' > "
            + root.dir + "/leonie.vcf"]
        onExited: exitCode => {
            if (exitCode !== 0) { console.log("CONTACTS_FAIL could not seed vcards"); return; }
            contacts.loadFrom(root.dir);
        }
    }
}
