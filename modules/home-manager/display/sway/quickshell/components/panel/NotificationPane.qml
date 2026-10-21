import QtQuick
import ".."

// The notification centre, grouped by the app that sent them, with the
// audio controls welded underneath.
//
// A group is collapsed by default and shows its newest entry with a count.
// Five messages from one chat app is one thing that happened, and five
// identical plates is how a list stops being readable. Click a group to
// see all of it; click again to put it away.
//
// `groups` is a plain list so a fixture can feed it the ugly cases - no
// body, no app name, a body the size of a small file - without a
// notification bus being involved.
Item {
    id: root

    property real uiScale: 1
    // [{ app, items: [...], count }]
    property var groups: []

    // A flood of two hundred must not become two hundred delegates, so there
    // is still a ceiling - but it sits far above a normal desktop's worth of
    // noise. Below it everything is drawn and reached by scrolling; the "and
    // N more" lines are now the pathological case, not the everyday one.
    readonly property int maxGroups: 30
    readonly property int maxInGroup: 30

    // Both owned by ControlPanel; this pane only draws them. Keyed by
    // group key and by uid, never by index: the list reshuffles under
    // them every time something arrives.
    property var expanded: ({})

    // The selected notification, by uid. Clicking one selects it and prints
    // the whole thing; Delete removes it. Selection rather than
    // click-to-dismiss because reading a long notification used to require
    // destroying it.
    //
    // OWNED BY THE PANEL, not by this pane. The pane lives inside a
    // Variants delegate - one per screen - and ids in there are invisible
    // to the IPC handler at the top of ControlPanel, so the Delete key
    // reached a `notifyPane` that did not exist. Keeping the state outside
    // also means two screens cannot disagree about what is selected.
    property var selectedUids: []

    function isSelected(uid) { return selectedUids.indexOf(uid) >= 0 }

    signal clearAllAsked
    signal groupCleared(string app)
    signal dismissed(var item)
    signal selectRequested(string uid, bool extend)
    signal toggleRequested(string key)

    default property alias footer: footerSlot.data

    // How far down the list we are. Writable, and the only handle a fixture
    // has on the scroll: the render harness delivers no pointer events at
    // all - a bare MouseArea in it never sees a press - so neither a wheel
    // nor a drag can be asserted from a render.
    property alias scrollY: listClip.contentY

    readonly property int total: {
        let n = 0;
        for (const g of groups) n += g.count;
        return n;
    }

    Item {
        id: head
        width: parent.width
        height: 18 * root.uiScale

        Text {
            text: "Notifications"
            color: "@clockColor@"
            font.pixelSize: Math.round(13 * root.uiScale)
            font.weight: Font.DemiBold
        }

        Text {
            id: clearAll
            x: parent.width - width
            text: root.total === 0 ? "" : "Clear all"
            color: clearArea.containsMouse ? "@clockColor@" : "@mutedColor@"
            font.pixelSize: Math.round(11.5 * root.uiScale)

            MouseArea {
                id: clearArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.clearAllAsked()
            }
        }
    }

    Text {
        y: head.height + 12 * root.uiScale
        visible: root.total === 0
        text: "Nothing waiting."
        color: "@mutedColor@"
        font.pixelSize: Math.round(12.5 * root.uiScale)
    }

    // The list is clipped to its zone - content must never land over the
    // audio controls below or outside the sheet - and SCROLLS inside it.
    // Truncating instead ("and 8 more apps") made the apps underneath
    // unreachable, which is the one thing a notification centre may not do.
    Flickable {
        id: listClip
        y: head.height + 10 * root.uiScale
        width: parent.width
        height: Math.max(0, footerSlot.y - 14 * root.uiScale - y)
        clip: true

        contentWidth: width
        contentHeight: list.height
        // No bounce. A rubber-band at the ends of a seven-centimetre column
        // reads as the sheet itself coming loose.
        boundsBehavior: Flickable.StopAtBounds

        // The wheel moves contentY without ever setting `moving`, so the
        // indicator cannot hang off that; it hangs off the position
        // actually changing, and goes quiet when it stops.
        property bool scrolling: false
        onContentYChanged: { scrolling = true; idle.restart() }
        Timer { id: idle; interval: 650; onTriggered: listClip.scrolling = false }

    Column {
        id: list
        width: listClip.width
        spacing: 8 * root.uiScale

        // Clearing one group slides the rest up into the gap.
        move: Transition {
            NumberAnimation { properties: "y"; duration: 180
                              easing.type: Easing.OutCubic }
        }

        Repeater {
            model: root.groups.slice(0, root.maxGroups)

            Rectangle {
                id: group
                required property var modelData

                readonly property bool open:
                    root.expanded[modelData.key] === true
                readonly property bool stacked: modelData.count > 1

                width: list.width
                height: body.implicitHeight + 18 * root.uiScale
                radius: 12 * root.uiScale
                color: "@plateBg@"
                clip: true


                // Opening a group grows the plate rather than snapping it.
                // The delegate survives the toggle - `expanded` is keyed on
                // the app name and does not rebuild `groups` - so a plain
                // Behavior is enough, and clip:true above means the entries
                // are revealed by the growing edge rather than spilling out
                // of a box that has not caught up yet.
                Behavior on height {
                    NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
                }

                // So the accent edge follows the rounded corners instead of
                // leaving a wedge of ground at each end of it.
                Rectangle {
                    width: 2 * root.uiScale
                    height: parent.height
                    radius: width
                    color: "@greenColor@"
                }

                Column {
                    id: body
                    x: 13 * root.uiScale
                    y: 9 * root.uiScale
                    width: parent.width - 26 * root.uiScale
                    spacing: 6 * root.uiScale

                    // ---- the group's own line ----
                    Item {
                        width: parent.width
                        height: appName.implicitHeight

                        Text {
                            id: appName
                            text: group.modelData.app
                            color: "@mutedColor@"
                            font.pixelSize: Math.round(10 * root.uiScale)
                            font.weight: Font.Medium
                        }

                        // The count, only when there is more than one - a
                        // "1" badge on every single notification is noise.
                        Rectangle {
                            visible: group.stacked
                            x: appName.implicitWidth + 7 * root.uiScale
                            y: -1 * root.uiScale
                            width: countText.implicitWidth + 10 * root.uiScale
                            height: countText.implicitHeight + 2 * root.uiScale
                            radius: height / 2
                            color: "@greenColor@"

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                text: group.modelData.count
                                color: "@onAccentInk@"
                                font.pixelSize: Math.round(9.5 * root.uiScale)
                                font.weight: Font.DemiBold
                            }
                        }

                        Text {
                            x: parent.width - width
                            visible: group.stacked
                            text: group.open ? "Collapse" : "Expand"
                            color: "@mutedColor@"
                            font.pixelSize: Math.round(10 * root.uiScale)
                        }
                    }

                    // ---- collapsed: the newest one only ----
                    Item {
                        visible: !group.open
                        width: parent.width
                        height: visible ? lone.implicitHeight : 0

                        Rectangle {
                            visible: !group.stacked
                                && root.isSelected(group.modelData.items[0].uid)
                            x: -7 * root.uiScale
                            y: -3 * root.uiScale
                            width: parent.width + 14 * root.uiScale
                            height: lone.implicitHeight + 6 * root.uiScale
                            radius: 7 * root.uiScale
                            color: "@plateBg@"
                        }

                        NotificationRow {
                            id: lone
                            width: parent.width
                            uiScale: root.uiScale
                            showApp: false
                            showSummary: group.modelData.relay !== true
                            item: group.modelData.items[0]
                            expanded: !group.stacked
                                && root.isSelected(group.modelData.items[0].uid)
                        }
                    }

                    // ---- expanded: all of them ----
                    Repeater {
                        model: group.open
                            ? group.modelData.items.slice(0, root.maxInGroup)
                            : []

                        Item {
                            required property var modelData
                            required property int index
                            width: body.width
                            height: row.implicitHeight + (index > 0 ? 9 : 0) * root.uiScale

                            PanelBeam {
                                visible: index > 0
                                horizontal: true
                                width: parent.width
                                y: 0
                            }

                            // Selection marks the ROW, because that is what
                            // is selected. Outlining the whole group put a
                            // green rectangle around the green edge it
                            // already had and read as a rendering fault.
                            Rectangle {
                                visible: root.isSelected(modelData.uid)
                                x: -7 * root.uiScale
                                y: row.y - 3 * root.uiScale
                                width: parent.width + 14 * root.uiScale
                                height: row.implicitHeight + 6 * root.uiScale
                                radius: 7 * root.uiScale
                                color: "@plateBg@"
                            }

                            NotificationRow {
                                id: row
                                y: (index > 0 ? 9 : 0) * root.uiScale
                                width: parent.width
                                uiScale: root.uiScale
                                showApp: false
                                showSummary: group.modelData.relay !== true
                                item: modelData
                                expanded: root.isSelected(modelData.uid)

                                // Each one a beat behind the last, so an
                                // opening group reads as unfolding rather
                                // than as a block arriving.
                                opacity: 0
                                Component.onCompleted: reveal.start()
                                SequentialAnimation {
                                    id: reveal
                                    PauseAnimation { duration: 40 + index * 45 }
                                    NumberAnimation {
                                        target: row; property: "opacity"
                                        to: 1; duration: 150
                                    }
                                }
                            }

                            // In an open group each entry is its own target.
                            MouseArea {
                                anchors.fill: parent
                                onClicked: mouse => root.selectRequested(modelData.uid,
                                        (mouse.modifiers & Qt.ShiftModifier) !== 0)
                            }
                        }
                    }

                    Text {
                        visible: group.open
                            && group.modelData.count > root.maxInGroup
                        text: "and " + (group.modelData.count - root.maxInGroup)
                              + " more"
                        color: "@mutedColor@"
                        font.pixelSize: Math.round(11 * root.uiScale)
                    }
                }

                // Collapsed, the whole plate toggles. Open, only the header
                // does - the entries underneath are their own targets.
                MouseArea {
                    anchors.fill: parent
                    anchors.bottomMargin: group.open
                        ? parent.height - 26 * root.uiScale : 0
                    onClicked: mouse => {
                        if (group.stacked) root.toggleRequested(group.modelData.key);
                        else root.selectRequested(group.modelData.items[0].uid,
                                    (mouse.modifiers & Qt.ShiftModifier) !== 0);
                    }
                }
            }
        }

        Text {
            visible: root.groups.length > root.maxGroups
            text: "and " + (root.groups.length - root.maxGroups) + " more apps"
            color: "@mutedColor@"
            font.pixelSize: Math.round(11.5 * root.uiScale)
        }
    }
    }

    // How far down the list you are, and how much of it you are seeing. It
    // shows itself while the list moves and gets out of the way afterwards -
    // a permanent bar down the edge of a five-plate column is furniture.
    Rectangle {
        readonly property real ratio:
            listClip.contentHeight > 0
                ? Math.min(1, listClip.height / listClip.contentHeight) : 1

        visible: listClip.contentHeight > listClip.height + 1
        x: root.width - width
        width: 3 * root.uiScale
        height: Math.max(24 * root.uiScale, listClip.height * ratio)
        y: listClip.y + (listClip.height - height)
           * (listClip.contentHeight > listClip.height
              ? listClip.contentY / (listClip.contentHeight - listClip.height)
              : 0)
        radius: width
        color: "@mutedColor@"

        opacity: listClip.scrolling ? 0.75 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // Audio lives below a beam at the bottom of this column.
    PanelBeam {
        horizontal: true
        width: root.width
        y: footerSlot.y - 12 * root.uiScale
        visible: footerSlot.children.length > 0
    }

    Item {
        id: footerSlot
        width: root.width
        height: childrenRect.height
        y: root.height - height
    }
}
