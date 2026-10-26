import QtQuick
import Quickshell
import Quickshell.Wayland

// The layer a message toast lives on. Its own surface, top right, under the
// notification toasts - a text and a build failure are different kinds of
// news and stacking them in one column makes both harder to read.
//
// Keyboard focus is OnDemand and the surface takes the pointer only where a
// toast actually is, so the rest of the screen stays clickable and your
// typing stays where it was until you click the reply field.
//
// A toast that is being replied to does not expire. Nothing is ruder than a
// box that vanishes mid-sentence.
PanelWindow {
    id: root

    property real uiScale: 1
    property var core: null

    readonly property int lifeMs: 8000
    readonly property int maxShown: 3

    signal paneAsked(string convId)

    // [{ convId, title, initials, hue, preview, born }] - newest first.
    property var live: []

    function show(msg): void {
        if (!msg) return;
        const conv = root.core ? root.core.conversationFor(msg.convId) : null;
        const entry = {
            convId: msg.convId,
            title: conv ? conv.title : (msg.addresses[0] || ""),
            initials: conv ? conv.initials : "",
            hue: conv ? conv.hue : "@mutedColor@",
            preview: msg.body && msg.body.length > 0 ? msg.body : "Attachment",
            born: Date.now()
        };
        // One toast per conversation. Three texts in a row from the same
        // person is one conversation, not a stack - the newest body wins and
        // the clock restarts.
        let next = root.live.filter(e => e.convId !== entry.convId);
        next.unshift(entry);
        root.live = next.slice(0, root.maxShown);
    }

    function dismiss(convId): void {
        root.live = root.live.filter(e => e.convId !== convId);
    }

    anchors { top: true; right: true }
    // Tall enough for the stack, wide enough for one toast plus its margin.
    implicitWidth: 420 * root.uiScale
    implicitHeight: Math.max(1, column.implicitHeight + 24 * root.uiScale)
    visible: root.live.length > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // The pointer only where a toast is. Without this the whole top-right
    // corner of the screen stops being clickable whenever a text arrives.
    mask: Region { item: column }

    Timer {
        running: root.live.length > 0
        interval: 500
        repeat: true
        onTriggered: {
            const now = Date.now();
            root.live = root.live.filter(e =>
                e.replying === true || now - e.born < root.lifeMs);
        }
    }

    Column {
        id: column
        x: 12 * root.uiScale
        y: 12 * root.uiScale
        width: 380 * root.uiScale
        spacing: 8 * root.uiScale

        Repeater {
            model: root.live

            delegate: MessageToast {
                required property var modelData
                required property int index

                uiScale: root.uiScale
                title: modelData.title
                initials: modelData.initials
                preview: modelData.preview
                hue: modelData.hue
                convId: modelData.convId

                // Marks the entry so the expiry timer leaves it alone while
                // you are typing into it.
                onReplyingChanged: {
                    let next = root.live.slice();
                    if (next[index]) next[index].replying = replying;
                    root.live = next;
                }

                onReplySent: text => {
                    if (root.core) root.core.replyTo(modelData.convId, text);
                    // Left up briefly showing "Sent" rather than vanishing on
                    // the keystroke, so you can see that it went.
                    sentTimer.target = modelData.convId;
                    sentTimer.restart();
                }

                onPaneAsked: {
                    root.dismiss(modelData.convId);
                    root.paneAsked(modelData.convId);
                }

                onDismissed: root.dismiss(modelData.convId)
            }
        }
    }

    Timer {
        id: sentTimer
        property string target: ""
        interval: 1400
        repeat: false
        onTriggered: root.dismiss(target)
    }
}
