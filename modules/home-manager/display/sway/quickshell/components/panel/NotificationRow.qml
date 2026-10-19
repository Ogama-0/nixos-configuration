import QtQuick
import Quickshell

// One notification's text. Shared by the centre and the toasts so the two
// cannot drift apart - a toast that looks different from its own entry in
// the list is two designs for one thing.
Item {
    id: root

    property real uiScale: 1
    property var item: null
    property bool showApp: true
    // Selected rows print the whole thing. A one-line body is the right
    // default for a list you are scanning and the wrong one the moment you
    // have picked the message you actually want to read.
    property bool expanded: false

    // The sender's own icon, when it has one that resolves. `image` is the
    // notification's own picture and beats `appIcon`, which is the app's.
    // Neither is required: plenty of senders set no icon at all, and a
    // broken-image placeholder is worse than none.
    readonly property string iconSource: {
        if (!item) return "";
        if (item.image) return Quickshell.iconPath(item.image, true);
        if (item.appIcon) return Quickshell.iconPath(item.appIcon, true);
        return "";
    }
    readonly property bool hasIcon: iconSource !== ""

    implicitHeight: Math.max(col.implicitHeight,
                             hasIcon ? 26 * uiScale : 0)

    Image {
        id: logo
        visible: root.hasIcon
        source: root.iconSource
        width: 22 * root.uiScale
        height: width
        y: 1 * root.uiScale
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
    }

    Column {
        id: col
        x: root.hasIcon ? logo.width + 9 * root.uiScale : 0
        width: parent.width - x
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
            wrapMode: root.expanded ? Text.Wrap : Text.NoWrap
            maximumLineCount: root.expanded ? 3 : 1
        }
        Text {
            width: parent.width
            // One line when scanning. A body can be kilobytes long and must
            // not be allowed to set this row's height - so even expanded it
            // stops at eight lines rather than taking the whole panel.
            text: root.item && root.item.summary ? (root.item.body || "") : ""
            visible: text.length > 0
            color: "@mutedColor@"
            font.pixelSize: Math.round(12 * root.uiScale)
            elide: Text.ElideRight
            wrapMode: root.expanded ? Text.Wrap : Text.NoWrap
            maximumLineCount: root.expanded ? 8 : 1
        }
    }
}
