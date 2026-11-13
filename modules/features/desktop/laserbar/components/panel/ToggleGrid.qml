import QtQuick

// The toggle block: four columns, two rows, with the lock spanning two
// columns on the second row.
//
// `items` is a plain list of { key, icon, name, active, action } so the grid
// can be rendered from a stub in a render fixture without the real backends
// being anywhere near it. ToggleModel.qml produces the real one.
//
// Explicit x/y arithmetic rather than a Grid: positioners are forbidden for
// anything that animates, and this sits inside a sheet that animates on
// every summon.
Item {
    id: root

    property var items: []
    property real uiScale: 1
    property real gap: 9

    signal activated(string key)
    signal tileHovered(string key, real centreX, real topY, bool entered)

    readonly property real tileW: (width - 3 * gap * uiScale) / 4
    readonly property real tileH: (height - gap * uiScale) / 2

    // Column and row per item, accumulated rather than derived from the
    // index: the lock spans two columns, so everything after it is pushed
    // along by one and index arithmetic alone gets it wrong. Reordering the
    // list is still the only edit needed to reorder the grid.
    readonly property var slots: {
        const out = [];
        let col = 0, row = 0;
        for (let i = 0; i < items.length; i++) {
            const span = items[i].action === true ? 2 : 1;
            if (col + span > 4) { col = 0; row++; }
            out.push({ col: col, row: row, span: span });
            col += span;
        }
        return out;
    }

    Repeater {
        model: root.items

        ToggleTile {
            required property var modelData
            required property int index

            readonly property var slot: root.slots[index]

            x: slot.col * (root.tileW + root.gap * root.uiScale)
            y: slot.row * (root.tileH + root.gap * root.uiScale)
            width: slot.span * root.tileW + (slot.span - 1) * root.gap * root.uiScale
            height: root.tileH

            uiScale: root.uiScale
            iconName: modelData.icon
            label: modelData.name
            active: modelData.active === true
            isAction: modelData.action === true

            onActivated: root.activated(modelData.key)
            onHoverEntered: entered =>
                root.tileHovered(modelData.key, x + width / 2, y, entered)
        }
    }
}
