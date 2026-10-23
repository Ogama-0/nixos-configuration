import QtQuick
import Quickshell
import "components"

// The selection arithmetic, driven with literals.
//
// None of it can be reached through a render: it needs a notification bus,
// a pointer and a keyboard. It is also the part where being subtly wrong is
// invisible - a shift-range off by one, or a delete that lands on nothing.
Scope {
    ControlPanel {
        id: cp
        Component.onCompleted: {
            const groups = [
                { key: "g1", items: [{ uid: "a" }, { uid: "b" }, { uid: "c" }] },
                { key: "g2", items: [{ uid: "d" }] },
                { key: "g3", items: [{ uid: "e" }, { uid: "f" }] }
            ];

            // The caps come off the panel, so this exercises the real ones
            // rather than a pair of literals that can drift away from them -
            // which is what they had done: the pane drew 30 groups of 30
            // while the order was hardcoded to 5 and 6, and every selection
            // past the fifth group was computed against a list that did not
            // match the screen.
            const gc = cp.maxGroups, ic = cp.maxInGroup;
            console.log("CAPS            groups=" + gc + " items=" + ic);

            console.log("ORDER_COLLAPSED " + cp.visibleOrderOf(groups, ({}), gc, ic).join(","));
            console.log("ORDER_OPEN      " + cp.visibleOrderOf(groups, ({ "g1": true }), gc, ic).join(","));

            // The caps still cap. Two groups of the three, two items of g1's
            // three: b survives, c is past the item cap, g3 past the group
            // cap. A cap that silently stopped applying would be just as
            // wrong as one that disagrees with the pane.
            console.log("ORDER_CAPPED    "
                + cp.visibleOrderOf(groups, ({ "g1": true }), 2, 2).join(","));

            const order = cp.visibleOrderOf(groups, ({ "g1": true }), gc, ic);  // a,b,c,d,e

            console.log("CLICK           " + cp.selectionFor(order, [], "", "b", false).join(","));
            console.log("CLICK_AGAIN     " + cp.selectionFor(order, ["b"], "b", "b", false).join(","));
            console.log("SHIFT_FORWARD   " + cp.selectionFor(order, ["a"], "a", "c", true).join(","));
            console.log("SHIFT_BACKWARD  " + cp.selectionFor(order, ["d"], "d", "b", true).join(","));
            console.log("SHIFT_NO_ANCHOR " + cp.selectionFor(order, [], "", "c", true).join(","));

            console.log("NEXT_MIDDLE     " + cp.nextAfter(order, ["b"]));
            console.log("NEXT_RANGE      " + cp.nextAfter(order, ["a", "b", "c"]));
            console.log("NEXT_LAST       " + cp.nextAfter(order, ["e"]));
            console.log("NEXT_ALL        '" + cp.nextAfter(order, order) + "'");
        }
    }
}
