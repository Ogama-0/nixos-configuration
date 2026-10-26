import QtQuick

// The thread: a header, a river of bubbles, and whatever the phone has sent
// us of the history so far.
//
// Newest at the bottom, which is the one thing every messaging app agrees on
// and the one thing a ListView does not do by default. `verticalLayoutDirection`
// handles it by flipping the view, which also means the model arrives
// newest-first - the same order MessageStore hands it back in, so nothing
// re-sorts anything.
//
// Reaching the top asks for another page. That request goes out ONCE per
// page: `loadingOlder` is owned by whoever is doing the fetching, and this
// will not ask again until they clear it. Without that guard a flick to the
// top fires a request per frame.
//
// Delivery is a claim this pane is careful about. sendSms returns nothing -
// there is no receipt - so a message is "Sent" until the phone echoes it back
// in a later conversationUpdated, and only then "Delivered". It never flips
// on a timer.
Item {
    id: root

    property real uiScale: 1

    property string title: ""
    property string initials: ""
    property color hue: "@mutedColor@"

    // Newest first.
    property var messages: []
    property bool loadingOlder: false

    signal olderWanted()
    signal infoAsked()

    // A wash that darkens in BOTH variants.
    //
    // @glassBg@ cannot do this: it is 40% of base00, and base00 is black in
    // dark but the CREAM GROUND in light - so on the crimson bubble it
    // lightened the recess into a pink panel. @msgAccentInk@ is the one
    // value that is near-black in both (base00 dark, base07 light), which is
    // exactly why it is the ink on the accent fill in the first place.
    readonly property color accentInk: "@msgAccentInk@"
    readonly property color bubbleRecess: Qt.rgba(accentInk.r, accentInk.g,
                                                  accentInk.b, 0.32)

    function dayLabel(ts: real): string {
        const d = new Date(ts);
        const now = new Date();
        if (d.toDateString() === now.toDateString())
            return "Today " + Qt.formatTime(d, "HH:mm");
        const yesterday = new Date(now.getTime() - 86400000);
        if (d.toDateString() === yesterday.toDateString())
            return "Yesterday " + Qt.formatTime(d, "HH:mm");
        return Qt.formatDate(d, "dddd d MMMM");
    }

    // ---- header ----

    Item {
        id: head
        x: 20 * root.uiScale
        y: 0
        width: parent.width - 40 * root.uiScale
        height: 52 * root.uiScale

        MessageAvatar {
            id: headAvatar
            anchors.verticalCenter: parent.verticalCenter
            size: 26
            uiScale: root.uiScale
            initials: root.initials
            label: root.title
            hue: root.hue
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: headAvatar.width + 10 * root.uiScale
            width: parent.width - x - 30 * root.uiScale
            text: root.title
            color: "@clockColor@"
            font.pixelSize: Math.round(14 * root.uiScale)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: headRule
        y: head.height
        width: parent.width
        height: 1
        color: "@glassBorder@"
    }

    // ---- the river ----

    ListView {
        id: river
        x: 0
        y: headRule.y + 1
        width: parent.width
        height: parent.height - y - compose.height
        clip: true
        model: root.messages
        // Newest at the bottom while the model is newest-first. The
        // alternative is reversing the array on every update, which would
        // rebuild every delegate each time a message lands.
        verticalLayoutDirection: ListView.BottomToTop
        cacheBuffer: 300 * root.uiScale
        boundsBehavior: Flickable.StopAtBounds

        // Flipped, so "the top" is the END of the view.
        onAtYEndChanged: if (atYEnd && !root.loadingOlder) root.olderWanted()

        // FOOTER, not header. The view is flipped, so ListView's "header"
        // is pinned to the bottom of the screen next to the newest message -
        // which is where the first version put "Loading earlier messages".
        footer: Item {
            width: river.width
            height: root.loadingOlder ? 34 * root.uiScale : 8 * root.uiScale
            Rectangle {
                visible: root.loadingOlder
                anchors.centerIn: parent
                width: loadingText.implicitWidth + 24 * root.uiScale
                height: 22 * root.uiScale
                radius: height / 2
                color: "@plateBg@"

                Text {
                    id: loadingText
                    anchors.centerIn: parent
                    text: "Loading earlier messages…"
                    color: "@mutedColor@"
                    font.pixelSize: Math.round(11 * root.uiScale)
                }
            }
        }

        delegate: Column {
            id: entry
            required property var modelData
            required property int index

            width: river.width
            spacing: 3 * root.uiScale
            bottomPadding: 4 * root.uiScale

            readonly property bool outgoing: modelData.outgoing === true
            readonly property var atts: modelData.attachments || []

            // A fixed intrinsic width, NOT one derived from the bubble. The
            // first version sized the attachment from its parent while the
            // bubble sized itself from the attachment, and QML resolved that
            // circle by collapsing both to nothing - a photo rendered as a
            // 20px sliver.
            readonly property real attWidth: atts.length > 0 ? 188 * root.uiScale : 0

            // The model is newest-first, so the message BEFORE this one in
            // time is the next index up. A separator belongs above a message
            // that opens a new day - or above the oldest one we hold.
            readonly property bool opensDay: {
                const older = river.model[entry.index + 1];
                if (!older) return true;
                return new Date(older.ts).toDateString()
                    !== new Date(entry.modelData.ts).toDateString();
            }

            Item {
                visible: entry.opensDay
                width: parent.width
                height: entry.opensDay ? 26 * root.uiScale : 0

                Text {
                    anchors.centerIn: parent
                    text: root.dayLabel(entry.modelData.ts)
                    color: "@mutedColor@"
                    font.pixelSize: Math.round(11 * root.uiScale)
                }
            }

            // ---- the bubble ----

            Item {
                width: parent.width
                height: bubble.height

                Rectangle {
                    id: bubble
                    x: entry.outgoing
                        ? parent.width - width - 20 * root.uiScale
                        : 20 * root.uiScale
                    width: Math.min(parent.width * 0.64,
                                    Math.max(bodyText.implicitWidth, entry.attWidth)
                                    + 28 * root.uiScale)
                    height: content.implicitHeight + 18 * root.uiScale
                    radius: 17 * root.uiScale
                    color: entry.outgoing ? "@msgAccent@" : "@plateBg@"

                    // The corner nearest the tail squares off. Both sides,
                    // because a bubble with four equal corners reads as a
                    // card and loses which end of the conversation it came
                    // from at a glance.
                    Rectangle {
                        width: parent.radius
                        height: parent.radius
                        color: parent.color
                        x: entry.outgoing ? parent.width - width : 0
                        y: parent.height - height
                    }

                    Column {
                        id: content
                        x: 14 * root.uiScale
                        y: 9 * root.uiScale
                        width: parent.width - 28 * root.uiScale
                        spacing: 6 * root.uiScale

                        Text {
                            id: bodyText
                            visible: text.length > 0
                            width: parent.width
                            text: entry.modelData.body || ""
                            color: entry.outgoing ? "@msgAccentInk@" : "@clockColor@"
                            font.pixelSize: Math.round(13.5 * root.uiScale)
                            wrapMode: Text.Wrap
                        }

                        Column {
                            id: attColumn
                            width: parent.width
                            spacing: 6 * root.uiScale

                            Repeater {
                                model: entry.atts
                                delegate: Item {
                                    required property var modelData
                                    width: entry.attWidth
                                    height: 126 * root.uiScale

                                    Image {
                                        id: att
                                        anchors.fill: parent
                                        visible: parent.modelData.path !== ""
                                        source: parent.modelData.path !== ""
                                            ? "file://" + parent.modelData.path : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        // The bubble already clips to its
                                        // radius; this keeps the crop from
                                        // squaring the corners back off.
                                        layer.enabled: true
                                    }

                                    // Not a broken-image glyph and not a blank
                                    // box: the file lives on the phone until
                                    // it is asked for, and that is a state
                                    // worth naming.
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: !att.visible
                                        radius: 11 * root.uiScale
                                        // Reads as a recess in the bubble.
                                        // See root.bubbleRecess for why this
                                        // is not @glassBorder@ (a light wash,
                                        // looked like a brighter button on
                                        // top) and not @glassBg@ (lightens in
                                        // the light variant).
                                        color: root.bubbleRecess

                                        Text {
                                            anchors.centerIn: parent
                                            width: parent.width - 20 * root.uiScale
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                            text: (parent.parent.modelData.name || "Attachment")
                                                + "\non the phone — click to fetch"
                                            color: entry.outgoing
                                                ? "@msgAccentInk@" : "@mutedColor@"
                                            font.pixelSize: Math.round(11 * root.uiScale)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Only under the newest outgoing message, which in a
            // newest-first model is index 0. A "Delivered" under every
            // bubble is noise, and under an old one it is archaeology.
            Item {
                visible: entry.outgoing && entry.index === 0
                width: parent.width
                height: visible ? 14 * root.uiScale : 0

                Text {
                    x: parent.width - width - 22 * root.uiScale
                    text: entry.modelData.delivered === true ? "Delivered"
                        : entry.modelData.pending === true ? "Sending…" : "Sent"
                    color: "@mutedColor@"
                    font.pixelSize: Math.round(10.5 * root.uiScale)
                }
            }
        }
    }

    // The compose row is the next task's; this reserves its height so the
    // river does not lay out behind it and jump when it arrives.
    Item {
        id: compose
        y: parent.height - height
        width: parent.width
        height: 56 * root.uiScale
    }
}
