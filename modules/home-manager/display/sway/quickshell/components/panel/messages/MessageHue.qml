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

    // Parsed once. hueFor is called per delegate per frame in a list that
    // scrolls, which is the wrong place to be splitting a string.
    readonly property var hues: "@msgHues@".split(",").filter(s => s.length > 0)

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
