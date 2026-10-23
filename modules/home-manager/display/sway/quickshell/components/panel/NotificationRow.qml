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
    // A relayed notification's summary is the phone app's name, which the
    // group header already prints. Repeating it leaves the body - the only
    // part you actually read - as the smallest text in the row.
    property bool showSummary: true
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

    // The server advertises body-markup, so a sender writing "<b>" means
    // bold. StyledText rather than AutoText because the heuristic that picks
    // for us is not ours to rely on.
    //
    // Then the un-escaping, which is the whole reason this function exists.
    // KDE Connect escapes the phone app's markup before forwarding it, so a
    // WhatsApp message arrives as "&lt;b&gt;Helena&lt;/b&gt;&lt;br/&gt;" and
    // renders - correctly, for what it literally says - as the characters
    // <b>. Nobody meant those characters: the phone sent bold and a line
    // break, and one courier along the way spelled them out. Only the tags
    // the body-markup spec defines are put back, so a message that really
    // does contain "&lt;3" keeps it.
    //
    // A collapsed row then flattens the line breaks rather than honouring
    // them: it has one line to spend, and a <br> after the first word would
    // spend it on nothing.
    function markup(s) {
        const t = s.replace(/&lt;(\/?(?:b|i|u|br)\s*\/?)&gt;/gi, "<$1>");
        return expanded ? t : t.replace(/<br\s*\/?>/gi, " ");
    }

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
            visible: root.showSummary
            text: root.item
                ? root.markup(root.item.summary || root.item.body || "(no title)") : ""
            textFormat: Text.StyledText
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
            text: root.item
                ? (root.showSummary && !root.item.summary
                   ? "" : root.markup(root.item.body || ""))
                : ""
            textFormat: Text.StyledText
            visible: text.length > 0
            color: root.showSummary ? "@mutedColor@" : "@clockColor@"
            font.pixelSize: Math.round(12.5 * root.uiScale)
            font.weight: root.showSummary ? Font.Normal : Font.DemiBold
            elide: Text.ElideRight
            wrapMode: root.expanded ? Text.Wrap : Text.NoWrap
            maximumLineCount: root.expanded ? 8 : 1
        }
    }
}
