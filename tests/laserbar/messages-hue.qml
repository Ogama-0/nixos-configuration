import QtQuick
import Quickshell
import "components/panel/messages"

// One stable palette colour per contact.
//
// Three properties, and the first is the one that matters: a person's colour
// must not move. It is the only thing identifying them in a 62px circle with
// no photo in it, so a hue that changed between restarts - or between the
// pinned grid and the conversation header - would make the avatar useless as
// recognition.
//
// The third is the light variant's real constraint. Horizon light's base0A is
// #FBE0D9, near-white, and initials painted in it vanish into the cream sheet.
// It is excluded from the pool, and the only honest way to check that is to
// assert every colour handed out is a member of the pool the theme passed in.
//
// Logic fixture, not a render fixture: run it with
//   scripts/qml-logic-test.sh tests/laserbar/messages-hue.qml HUE_OK
ShellRoot {
    id: root

    MessageHue { id: hue }

    Component.onCompleted: {
        let bad = [];

        // Stable: the same number twice, and once more after a detour, is one
        // colour. Not a tautology - a hash seeded from anything per-call, or a
        // pool re-parsed in a different order, breaks exactly here.
        const a1 = String(hue.hueFor("+33767248570"));
        const a2 = String(hue.hueFor("+33767248570"));
        hue.hueFor("0600000000");
        const a3 = String(hue.hueFor("+33767248570"));
        if (a1 !== a2 || a1 !== a3)
            bad.push("unstable: " + a1 + " " + a2 + " " + a3);

        // Two spellings of one line are one person, so they are one colour.
        if (String(hue.hueFor("076-724-8570")) !== a1)
            bad.push("spelling changed the hue: " + hue.hueFor("076-724-8570") + " vs " + a1);

        // Spread: 50 numbers must not all land on one slot. Five distinct is a
        // floor, not a target - it catches a hash that collapsed, not one that
        // merely distributes unevenly.
        let seen = {};
        for (let i = 0; i < 50; i++) seen[String(hue.hueFor("06000000" + (10 + i)))] = true;
        const distinct = Object.keys(seen).length;
        if (distinct < 5) bad.push("only " + distinct + " distinct hues across 50 numbers");

        // Membership: every colour handed out came from the theme's pool.
        //
        // Both sides go through Qt.color() first. The pool is raw #AARRGGBB
        // text out of the theme token; what hueFor returns is a QColor, which
        // stringifies lowercase and drops a fully-opaque alpha - so "#FF273F"
        // and "#ff273f" are the same colour and compare unequal as strings.
        const pool = hue.hues.map(c => String(Qt.color(c)));
        if (pool.length === 0) bad.push("empty pool - @msgHues@ did not substitute");
        for (const got of Object.keys(seen))
            if (pool.indexOf(got) < 0) bad.push("hue outside the pool: " + got);

        // An empty number still has to render something rather than throw.
        if (!String(hue.hueFor(""))) bad.push("empty number yielded no colour");

        if (bad.length > 0) { console.log("HUE_FAIL " + bad.join(" | ")); return; }
        console.log("HUE_OK " + distinct + " distinct, pool " + pool.length);
    }
}
