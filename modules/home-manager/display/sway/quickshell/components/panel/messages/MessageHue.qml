import QtQuick

// A contact's colour. Non-visual.
//
// There are no contact photos - KDE Connect syncs 229 vCards and not one of
// them carries a PHOTO field - so in a 62px circle the only things telling
// two people apart are two letters and a colour. That makes the colour load
// bearing, and a colour that moved between restarts, or between the pinned
// grid and the conversation header, would be worse than no colour at all.
//
// So it is hashed from the number rather than assigned by position: the
// eighth conversation in the list is not "the eighth colour", it is whatever
// that person has always been, wherever they happen to be sitting today.
//
// The pool comes from the theme, per variant, and is NOT the same in both -
// light drops base0A, which is near-white there. Nothing in this file knows
// that; it just uses what it was handed.
Item {
    id: root

    // The pool as the theme gave it, before any correction.
    readonly property var rawHues: "@msgHues@".split(",").filter(s => s.length > 0)

    // What everything actually draws with: the same slots, dragged far enough
    // from the sheet to be seen on it.
    //
    // Horizon light needs this and dark does not. Its base0B is #94E1B0 and
    // its base0F is #E58C92 - pale mints and pinks that sit at about 1.3:1
    // against the #FDF0ED sheet. As initials they are unreadable and as a 2px
    // ring they are invisible, so a contact assigned one of them had no
    // avatar at all. Excluding them like base0A would leave four usable
    // slots for the whole address book.
    //
    // So they are darkened until they clear 4.5:1 rather than dropped. The
    // identity is still the palette slot; this is the same colour rendered
    // for the ground it is on, which is the same thing capsuleFill and
    // onAccentInk already do by hand per variant.
    //
    // Computed once over seven or eight entries at load. hueFor is called per
    // delegate in a list that scrolls and does no work beyond an index.
    readonly property var hues: rawHues.map(c => root.legible(c))

    readonly property color sheet: "@sheetBg@"

    function luminance(c: color): real {
        const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }

    function contrast(a: color, b: color): real {
        const la = root.luminance(a), lb = root.luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    function legible(spec): color {
        const ground = root.sheet;
        let c = Qt.color(spec);
        // Toward black on a light sheet, toward white on a dark one.
        const toward = root.luminance(ground) > 0.5 ? 0 : 1;
        // 12 steps of 8% is enough to clear 4.5:1 from anything in the
        // palette, and bails rather than looping if it is not.
        for (let i = 0; i < 12 && root.contrast(c, ground) < 4.5; i++) {
            c = Qt.rgba(c.r + (toward - c.r) * 0.08,
                        c.g + (toward - c.g) * 0.08,
                        c.b + (toward - c.b) * 0.08,
                        c.a);
        }
        return c;
    }

    // FNV-1a. Small, stable, and defined here rather than borrowed: JS has no
    // string hash of its own, and the obvious substitutes are all unstable -
    // object key order, Qt.md5 (not in QML), or anything seeded per run.
    //
    // `>>> 0` after every step keeps it in uint32. Without it the multiply
    // overflows into a double, precision goes, and two numbers that differ in
    // their last digits start colliding.
    //
    // NOT annotated `: int`. QML's int is a SIGNED 32-bit, so annotating it
    // takes the perfectly good uint32 this returns and wraps it negative -
    // hash("767248570") comes back as -1997306381 instead of 2297660915, and
    // a negative modulo indexes off the front of the pool and yields
    // undefined. Three of fifty numbers got a colour before this was caught.
    function hash(s: string) {
        let h = 0x811c9dc5;
        for (let i = 0; i < s.length; i++) {
            h ^= s.charCodeAt(i);
            h = Math.imul(h, 0x01000193) >>> 0;
        }
        return h >>> 0;
    }

    // Normalised first, so the two spellings of one line - +33767248570 off an
    // incoming SMS, 076-724-8570 out of the address book - are one person in
    // one colour. This duplicates ContactsModel.normalize deliberately: a hue
    // must still be stable when no contacts have loaded, and taking a
    // reference to that model here would couple every avatar to it.
    function keyFor(number: string): string {
        if (!number) return "";
        const digits = String(number).replace(/[^0-9]/g, "");
        if (digits.length === 0) return "";
        return digits.length > 9 ? digits.slice(-9) : digits;
    }

    function hueFor(number: string): color {
        if (root.hues.length === 0) return "#FF888888";
        return root.hues[root.hash(root.keyFor(number)) % root.hues.length];
    }
}
