import QtQuick

// One notification's text. Shared by the centre and the toasts so the two
// cannot drift apart - a toast that looks different from its own entry in
// the list is two designs for one thing.
Item {
    id: root

    property real uiScale: 1
    property var item: null
    property bool showApp: true

    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 2 * root.uiScale

        Text {
            visible: root.showApp
            width: parent.width
            // An app that does not name itself still gets a row.
            text: root.item ? (root.item.appName || "Unknown app") : ""
            color: "@mutedColor@"
            font.pixelSize: Math.round(10 * root.uiScale)
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: root.item
                ? (root.item.summary || root.item.body || "(no title)") : ""
            color: "@clockColor@"
            font.pixelSize: Math.round(12.5 * root.uiScale)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            // One line, elided. A body can be kilobytes long and must not
            // be allowed to set this row's height.
            text: root.item && root.item.summary ? (root.item.body || "") : ""
            visible: text.length > 0
            color: "@mutedColor@"
            font.pixelSize: Math.round(12 * root.uiScale)
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
