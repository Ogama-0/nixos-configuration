import QtQuick
// Quickshell, not just Quickshell.Io: load() reads Quickshell.env, and
// without this it is a ReferenceError the first time a real device id is
// passed. The fixture used loadFrom() and never touched it.
import Quickshell
import Quickshell.Io

// Who a phone number belongs to. Non-visual.
//
// KDE Connect's contacts plugin already syncs the phone's address book to
// disk as vCards, under ~/.local/share/kpeoplevcard/kdeconnect-<device>/ -
// 229 of them here. So turning a number into a name is a local file read and
// not a round-trip to a phone that may be asleep.
//
// What those cards do NOT carry is a single PHOTO field. Every one of them is
// a name and a number. That is the whole reason the avatars in this panel are
// colour and letterform instead of faces: there are no faces to draw.
//
// Nothing here is required to succeed. No contacts plugin, a device that was
// never paired, an empty directory: `ready` still turns true and every number
// resolves to itself with `known` false. A number with no card is not an
// error, it is a number you have not saved - which is most of them.
Item {
    id: root

    // True once a load has finished, successfully or not. Consumers wait on
    // this rather than on the Process, because "no cards at all" is a normal
    // outcome and still means the answer is ready.
    property bool ready: false

    // number -> { name, initials }, keyed by normalize().
    property var byNumber: ({})

    // The directory actually read. Set it directly to point at a different
    // set - the fixtures do - or go through load() for the usual one.
    property string vcardDir: ""

    function load(deviceId: string): void {
        if (!deviceId) { root.byNumber = ({}); root.ready = true; return; }
        root.loadFrom(Quickshell.env("HOME")
            + "/.local/share/kpeoplevcard/kdeconnect-" + deviceId);
    }

    function loadFrom(dir: string): void {
        root.vcardDir = dir;
        root.ready = false;
        // One `cat` over the glob, not one Process per file. At 229 cards the
        // per-process cost is the whole cost; the parse is nothing.
        readProc.command = ["sh", "-c", "cat " + dir + "/*.vcf 2>/dev/null || true"];
        readProc.running = true;
    }

    // Two spellings of one French mobile - +33767248570 off an incoming SMS,
    // 076-724-8570 out of the address book - have to land on the same key.
    // The trunk prefix and the country code are the same nine digits wearing
    // different hats, so the last nine are what identify a line.
    //
    // Shorter than nine digits is a shortcode (32665) and is already unique;
    // matching it on a suffix would fold unrelated ones together.
    //
    // And a sender can have no digits at all. Real traffic here arrives from
    // "Uber", "SIGNAL", "imagine R", "LBPCF" - alphanumeric sender IDs, which
    // are most of what a 2FA-heavy inbox contains. Stripping to digits maps
    // every one of them to "", so they shared a key, a name and a colour
    // until the first real payload showed up.
    function normalize(number: string): string {
        if (!number) return "";
        const digits = String(number).replace(/[^0-9]/g, "");
        if (digits.length === 0) {
            // Case- and space-folded, so "imagine R" and "Imagine R" are one
            // sender. Prefixed so an all-letters id can never collide with a
            // numeric key.
            return "id:" + String(number).toLowerCase().replace(/\s+/g, "");
        }
        return digits.length > 9 ? digits.slice(-9) : digits;
    }

    // Always an object, never null: every call site renders something, and a
    // null here would make each of them write the same guard.
    function resolve(number: string): var {
        const key = root.normalize(number);
        const hit = key ? root.byNumber[key] : undefined;
        if (hit === undefined) {
            // The number stands in for the name. A shortcode has no better
            // label, and an unsaved mobile is still recognisable as itself.
            return { name: number || "", initials: "", number: number || "",
                     known: false };
        }
        return { name: hit.name, initials: hit.initials, number: number,
                 known: true };
    }

    // First letter of the first and last words. One word gives one letter -
    // a surname that is not there is not an empty string to reach for.
    function initialsFor(name: string): string {
        const words = String(name).trim().split(/\s+/).filter(w => w.length > 0);
        if (words.length === 0) return "";
        const first = words[0].charAt(0);
        if (words.length === 1) return first.toUpperCase();
        return (first + words[words.length - 1].charAt(0)).toUpperCase();
    }

    Process {
        id: readProc
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                let fn = "";
                let tels = [];

                const commit = () => {
                    if (fn) {
                        const initials = root.initialsFor(fn);
                        for (const t of tels) {
                            const key = root.normalize(t);
                            // First card wins. Two contacts sharing a line is
                            // rare and arbitrary; flapping between them as the
                            // directory order changes would be worse.
                            if (key && map[key] === undefined)
                                map[key] = { name: fn, initials: initials };
                        }
                    }
                    fn = "";
                    tels = [];
                };

                for (let line of this.text.split("\n")) {
                    line = line.trim();
                    if (line.startsWith("BEGIN:VCARD")) { fn = ""; tels = []; continue; }
                    if (line.startsWith("END:VCARD")) { commit(); continue; }
                    // FN: is the display name. N: is the structured one and is
                    // not used - it is semicolon-separated and the cards here
                    // fill it inconsistently.
                    if (line.startsWith("FN:")) { fn = line.slice(3).trim(); continue; }
                    // TEL;CELL:, TEL;HOME:, TEL;TYPE=CELL: - the parameters
                    // vary by exporter and none of them change the number.
                    if (line.startsWith("TEL")) {
                        const colon = line.indexOf(":");
                        if (colon >= 0) tels.push(line.slice(colon + 1).trim());
                    }
                }
                // A card the file ended mid-way through, without END:VCARD.
                commit();

                root.byNumber = map;
                root.ready = true;
            }
        }
        onExited: exitCode => {
            // `cat` over a glob that matched nothing still leaves us ready
            // with an empty map, which resolve() handles. Only a failure that
            // produced no stream at all lands here with ready still false.
            if (!root.ready) { root.byNumber = ({}); root.ready = true; }
        }
    }
}
