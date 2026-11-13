import QtQuick
import QtQuick.Effects

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
    // The one shared MessageAudio, forwarded from MessagesPane/MessagesCore
    // - see docs/messages-panel.md, "One player, not one per bubble". Every
    // VoiceBubble in the Repeater below is handed the SAME object, which is
    // the whole point: starting one note stops whatever was sounding.
    property var audio: null

    signal olderWanted()
    signal infoAsked()
    // (partID, uniqueIdentifier) - the two arguments requestAttachmentFile
    // takes. Raised by tapping an attachment that is still on the phone.
    signal attachmentAsked(int partId, string uid)
    // Raised by tapping a photo - either the one that is already showing
    // (`source` is its resolved URL) or the recess an image attachment
    // falls into when it has no bytes at all (`source` is "", and the
    // viewer's own `missing` text is what that empty string becomes -
    // Review Focus 5). `origin` is already in GLOBAL (window) coordinates,
    // not this delegate's own x/y - see the MouseAreas below for why.
    signal pictureAsked(string source, string who, real ts, rect origin)

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
        // No room reserved for the compose row here. It was, once, when the
        // compose row did not exist yet and this view was the whole right
        // half - and the reservation stayed after MessagesPane started
        // sizing this view as `parent.height - compose.height`. Both, so a
        // bubble's worth of thread was being hidden behind empty air.
        height: parent.height - y
        clip: true
        model: root.messages
        // Newest at the bottom while the model is newest-first. The
        // alternative is reversing the array on every update, which would
        // rebuild every delegate each time a message lands.
        verticalLayoutDirection: ListView.BottomToTop
        cacheBuffer: 300 * root.uiScale
        // See ThreadList's own comment on this same switch - a hard stop at
        // the ends felt stiff next to ordinary trackpad momentum scrolling.
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: 2500
        maximumFlickVelocity: 4000

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

            // A voice note is a row (button, bar, time), not a thumbnail -
            // it wants more width and a lot less height than a photo does.
            readonly property bool hasAudio:
                atts.some(a => String(a.mime || "").startsWith("audio/"))

            // A fixed intrinsic width, NOT one derived from the bubble. The
            // first version sized the attachment from its parent while the
            // bubble sized itself from the attachment, and QML resolved that
            // circle by collapsing both to nothing - a photo rendered as a
            // 20px sliver.
            readonly property real attWidth: atts.length === 0 ? 0
                : entry.hasAudio ? 224 * root.uiScale : 188 * root.uiScale

            // A photo with no caption gets no padding either - iMessage
            // fills the whole bubble with the image rather than floating it
            // in a frame of accent colour. A voice note keeps its padding
            // regardless (it is a control row, not a thumbnail, and a
            // play button flush against the bubble's own edge reads as
            // cut off rather than deliberate).
            readonly property bool bleeds: atts.length > 0 && !entry.hasAudio
                && !(modelData.body && modelData.body.length > 0)

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
                                    entry.bleeds ? entry.attWidth
                                        : Math.max(bodyText.implicitWidth, entry.attWidth)
                                          + 28 * root.uiScale)
                    height: content.implicitHeight + (entry.bleeds ? 0 : 18 * root.uiScale)
                    // A bled photo takes the SAME modest radius as its own
                    // corner mask below (11, not 17) - the ordinary chat
                    // bubble radius, blown up to cover a 188px-wide photo,
                    // read as a big diagonal wedge bitten out of the corner
                    // rather than the gentle iMessage-style round this was
                    // meant to match.
                    radius: (entry.bleeds ? 11 : 17) * root.uiScale
                    color: entry.outgoing ? "@msgAccent@" : "@plateBg@"
                    // Bounds insurance only. `clip` clips to an item's
                    // BOUNDING RECTANGLE, never to its `radius` - so this is
                    // not, and cannot be, what keeps a photo's square corners
                    // inside the bubble's rounded ones. The MultiEffect mask
                    // on the attachment Image below is the thing that does
                    // that; an earlier comment here credited this line with
                    // it, which would have led someone to delete the mask.
                    clip: true

                    // There is NO square-corner patch here, and there must
                    // not be one. A bubble whose tail corner squares off
                    // reads better - it says which end of the conversation
                    // the message came from - but the way to draw it is not
                    // a child Rectangle in `parent.color`:
                    //
                    // @plateBg@ is #12FFFAF3, a near-white at 7% alpha. The
                    // bubble lays that wash over the sheet once; a child in
                    // the same colour lays it down a SECOND time, and the
                    // corner comes out at double strength - measured at
                    // srgb(36,36,34) against the bubble's own srgb(19,19,18)
                    // - which on a dark ground reads as a white square stuck
                    // to the bubble. Outgoing bubbles hid it, because
                    // @msgAccent@ is opaque; every incoming one showed it.
                    //
                    // Doing it properly means an opaque bubble colour
                    // (plateBg composited onto sheetBg once, up front) so
                    // that a child in that colour is pixel-identical, or a
                    // Shape - and a ShapePath whose data changes draws
                    // nothing at all (rule 4), which a per-message bubble
                    // size guarantees. Until one of those is done, four
                    // equal corners is the honest look.

                    Column {
                        id: content
                        x: entry.bleeds ? 0 : 14 * root.uiScale
                        y: entry.bleeds ? 0 : 9 * root.uiScale
                        width: entry.bleeds ? parent.width : parent.width - 28 * root.uiScale
                        spacing: 6 * root.uiScale

                        // A TextEdit, not a Text, so the words can be
                        // selected and copied the way they can in any other
                        // messaging window. readOnly keeps it a label in
                        // every other respect.
                        //
                        // PlainText explicitly: a message body is whatever
                        // somebody typed, and TextEdit's RichText would
                        // happily render markup that arrived in an SMS.
                        TextEdit {
                            id: bodyText
                            visible: text.length > 0
                            width: parent.width
                            text: entry.modelData.body || ""
                            color: entry.outgoing ? "@msgAccentInk@" : "@clockColor@"
                            font.pixelSize: Math.round(13.5 * root.uiScale)
                            wrapMode: Text.Wrap
                            textFormat: TextEdit.PlainText
                            readOnly: true
                            selectByMouse: true

                            // The accent/ink pair either way round. Both
                            // orders are a designed contrast pair in BOTH
                            // variants, which a highlight built from
                            // @clockColor@ would not be - that one inverts
                            // between dark and light.
                            selectionColor: entry.outgoing
                                ? "@msgAccentInk@" : "@msgAccent@"
                            selectedTextColor: entry.outgoing
                                ? "@msgAccent@" : "@msgAccentInk@"

                            // Clicking a bubble gives it the keyboard, and a
                            // TextEdit swallows Escape by default - the same
                            // trap docs/messages-panel.md names for the
                            // search field and the compose box. Declining it
                            // here keeps Escape collapsing the pane from
                            // inside a message too.
                            Keys.onEscapePressed: event => event.accepted = false
                            // Delete and Backspace, on the other hand, are
                            // SWALLOWED. A read-only TextEdit ignores editing
                            // keys, which would let them bubble up to
                            // MessagesPane's Suppr handler and remove the
                            // conversation you were only trying to read.
                            // MessagesPane gates on the list having focus as
                            // well; this is the other half of that.
                            Keys.onDeletePressed: event => event.accepted = true
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Backspace)
                                    event.accepted = true;
                            }
                        }

                        Column {
                            id: attColumn
                            width: parent.width
                            spacing: 6 * root.uiScale

                            Repeater {
                                model: entry.atts
                                delegate: Item {
                                    id: attItem
                                    required property var modelData
                                    width: entry.attWidth
                                    // A voice note is a thin control row, not
                                    // a thumbnail. A photo sizes to its OWN
                                    // aspect ratio, like iMessage - cropping
                                    // it into a fixed 188x126 box was cutting
                                    // the top and bottom off anything that
                                    // was not already landscape-ish (a tall
                                    // phone photo, a poster, a screenshot
                                    // with text baked into the top/bottom).
                                    // 126 is only the guess shown before the
                                    // image has loaded and reported its own
                                    // size; clamped both ways so a panorama
                                    // cannot turn the bubble into a column
                                    // and a near-square photo does not go
                                    // flat.
                                    height: attItem.isAudio ? 48 * root.uiScale
                                        : (att.status === Image.Ready && att.implicitWidth > 0
                                            ? Math.max(100 * root.uiScale, Math.min(260 * root.uiScale,
                                                width * att.implicitHeight / att.implicitWidth))
                                            : 126 * root.uiScale)

                                    readonly property bool isImage:
                                        String(modelData.mime || "").startsWith("image/")
                                    readonly property bool isAudio:
                                        String(modelData.mime || "").startsWith("audio/")

                                    // Three ways an attachment can have its
                                    // bytes, and the first one is the common
                                    // one: docs/kdeconnect-sms-payload.md
                                    // says base64EncodedFile is empty until
                                    // fetched, and for IMAGES it is not -
                                    // they arrive inline on the first
                                    // announcement. Rendering only the
                                    // fetched path left every photo, including
                                    // the ones sent from this machine, sitting
                                    // behind "click to fetch" with its bytes
                                    // already in the cache.
                                    // Images only, both ways. A fetched voice
                                    // note has a path like any other
                                    // attachment, and handing an .amr to an
                                    // Image is a "Cannot open" in the log and
                                    // an empty box on screen - it was there,
                                    // in the first run of this.
                                    // `root.audio.fileUrl()` holds the
                                    // %-encoding rule, not a second copy of
                                    // it here: kdeconnect's own cache paths
                                    // carry a raw space AND a literal "%20"
                                    // (e.g. ".../Ogama phone/PART_...Mes1.amr")
                                    // and a bare "file://" + path leaves
                                    // both unescaped - the "%" needs to
                                    // become "%25" or the file is simply not
                                    // found. `encodeURI` does that (it is
                                    // not in its unreserved set) as a side
                                    // effect of the space encoding
                                    // MessageAudio's own fixture already
                                    // exercises.
                                    readonly property string src: !attItem.isImage ? ""
                                        : modelData.path
                                            ? (root.audio
                                               ? root.audio.fileUrl(modelData.path)
                                               : "file://" + modelData.path)
                                        : modelData.data
                                           ? "data:" + modelData.mime + ";base64,"
                                             + modelData.data
                                           : ""

                                    // What it is, for the cases there is
                                    // nothing to show: a voice note has no
                                    // thumbnail however many times it is
                                    // fetched. `name` was read here once and
                                    // parseMessage never produced one, so
                                    // every attachment read "Attachment".
                                    readonly property string label: {
                                        const m = String(modelData.mime || "");
                                        if (m.startsWith("image/")) return "Photo";
                                        if (m.startsWith("audio/")) return "Voice message";
                                        if (m.startsWith("video/")) return "Video";
                                        return "Attachment";
                                    }

                                    property bool asked: false

                                    Image {
                                        id: att
                                        anchors.fill: parent
                                        visible: attItem.src !== ""
                                                 && status !== Image.Error
                                        source: attItem.src
                                        // Crop, which for this box is the
                                        // same thing as Fit for every photo
                                        // whose ratio the height above was
                                        // allowed to match - and the right
                                        // answer for the ones it was not.
                                        // Fit letterboxed anything past the
                                        // clamp: an ordinary 9:16 phone
                                        // portrait wants 334px of height,
                                        // gets 260, and was then fitted to
                                        // 146px wide, leaving ~21px of bare
                                        // bubble down each side INSIDE the
                                        // rounded mask - accent colour, on an
                                        // outgoing one.
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true

                                        // An actual rounded-corner mask, not
                                        // four hand-placed circles standing
                                        // in for one - the quarter-circle
                                        // trick that used to live here read
                                        // as a separate round blob glued to
                                        // each corner rather than a clean
                                        // curve, because it is a visibly
                                        // different shape (a true circular
                                        // arc meeting a Rectangle's own
                                        // radius antialiasing at the same
                                        // nominal radius, drawn by two
                                        // unrelated draw calls) instead of
                                        // one continuous mask. RevealMask.qml
                                        // already proves the pattern works
                                        // in this renderer: `visible: false`
                                        // together with `layer.enabled: true`
                                        // on the mask item is what makes
                                        // MultiEffect actually grab it - an
                                        // earlier attempt here skipped one of
                                        // those two and got a blank image for
                                        // its trouble.
                                        // Images only. Every attachment
                                        // delegate owns this Image, and for
                                        // a voice note it is invisible with
                                        // an empty source - but an enabled
                                        // layer plus the mask's own below is
                                        // two framebuffers per bubble, paid
                                        // to round the corners of something
                                        // that never draws.
                                        layer.enabled: attItem.isImage
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: attMask
                                            maskThresholdMin: 0.0
                                            maskSpreadAtMin: 0.0
                                        }
                                    }

                                    Item {
                                        id: attMask
                                        anchors.fill: att
                                        visible: false
                                        // Paired with att.layer.enabled
                                        // above - a mask with nothing to
                                        // mask is a framebuffer for nothing.
                                        layer.enabled: attItem.isImage

                                        Rectangle {
                                            anchors.fill: parent
                                            // 11 either way, deliberately:
                                            // a bled photo's bubble takes
                                            // this same number (see
                                            // bubble.radius) so that its
                                            // edge and the mask's agree.
                                            // Written as a ternary on
                                            // bubble.radius, which resolved
                                            // to 11 in both branches.
                                            radius: 11 * root.uiScale
                                            color: "white"
                                        }
                                    }

                                    // Opens it full. `mapToItem(null, ...)`
                                    // rather than attItem.x/y - attItem
                                    // lives inside a delegate inside a
                                    // flipped ListView (ConversationView's
                                    // own header comment explains the flip),
                                    // so its OWN x/y are bubble-local and
                                    // meaningless as an animation origin;
                                    // `null` escapes all of that to the
                                    // window's own coordinates in one step,
                                    // which is what `ControlPanel.openPicture`
                                    // is written to receive back.
                                    MouseArea {
                                        anchors.fill: parent
                                        visible: att.visible
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const origin = attItem.mapToItem(
                                                null, 0, 0,
                                                attItem.width, attItem.height);
                                            root.pictureAsked(attItem.src,
                                                root.title, entry.modelData.ts,
                                                origin);
                                        }
                                    }

                                    // The voice note's own control row -
                                    // button, bar, time. It drives `audio`
                                    // directly and raises nothing, so there
                                    // is no handler to wire here beyond the
                                    // two properties it needs.
                                    VoiceBubble {
                                        anchors.fill: parent
                                        visible: attItem.isAudio
                                        uiScale: root.uiScale
                                        outgoing: entry.outgoing
                                        audio: root.audio
                                        msgId: entry.modelData.id
                                        attachment: attItem.modelData
                                        label: attItem.label
                                    }

                                    // Not a broken-image glyph and not a blank
                                    // box: the file lives on the phone until
                                    // it is asked for, and that is a state
                                    // worth naming.
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: !att.visible && !attItem.isAudio
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
                                            // An image with neither inline
                                            // bytes nor a path has nothing to
                                            // fetch - images arrive inline on
                                            // the first announcement or not
                                            // at all (ConversationView's
                                            // `src` comment above) - so it
                                            // gets a different label than the
                                            // "click to fetch" that applies
                                            // to everything else still on the
                                            // phone.
                                            text: attItem.isImage
                                                ? attItem.label + "\nnot sent"
                                                : attItem.label + "\n"
                                                    + (attItem.asked ? "fetching…"
                                                       : "on the phone — click to fetch")
                                            color: entry.outgoing
                                                ? "@msgAccentInk@" : "@mutedColor@"
                                            font.pixelSize: Math.round(11 * root.uiScale)
                                        }

                                        // Two different taps behind the same
                                        // recess. An image here is tapped to
                                        // open the full viewer on its
                                        // "missing" state (Review Focus 5) -
                                        // there is no fetch to ask for. Any
                                        // other attachment is "click to
                                        // fetch" and nothing was listening:
                                        // the file arrives later as
                                        // attachmentReceived and reaches the
                                        // bubble through the store, so there
                                        // is nothing to wait on here beyond
                                        // saying we asked.
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (attItem.isImage) {
                                                    const origin = attItem.mapToItem(
                                                        null, 0, 0,
                                                        attItem.width, attItem.height);
                                                    root.pictureAsked("",
                                                        root.title, entry.modelData.ts,
                                                        origin);
                                                    return;
                                                }
                                                attItem.asked = true;
                                                root.attachmentAsked(
                                                    attItem.modelData.partId,
                                                    String(attItem.modelData.uid || ""));
                                            }
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

}
