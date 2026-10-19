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

    // Drawn at most; the rest exist in the model and are counted, not laid
    // out. A flood of two hundred must not become two hundred delegates.
    readonly property int maxGroups: 5
    readonly property int maxInGroup: 6

    // Which app names are open. A plain object keyed by name, so it
    // survives the list reshuffling underneath it - an index would not.
    property var expanded: ({})

    signal clearAllAsked
    signal groupCleared(string app)
    signal dismissed(var item)

    default property alias footer: footerSlot.data

    function toggle(app) {
        const next = {};
        for (const k in expanded) next[k] = expanded[k];
        next[app] = !next[app];
        expanded = next;
    }

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

    // The list is BOUNDED and clipped. An expanded group of six on top of
    // four other apps is taller than the zone, and without this it drew
    // straight over the audio controls below and out of the sheet. The
    // counts already say what is not shown; what must never happen is
    // content landing somewhere it was not allocated.
    Item {
        id: listClip
        y: head.height + 10 * root.uiScale
        width: parent.width
        height: Math.max(0, footerSlot.y - 14 * root.uiScale - y)
        clip: true

    Column {
        id: list
        width: parent.width
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
                    root.expanded[modelData.app] === true
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
                    NotificationRow {
                        visible: !group.open
                        width: parent.width
                        uiScale: root.uiScale
                        showApp: false
                        item: group.modelData.items[0]
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

                            NotificationRow {
                                id: row
                                y: (index > 0 ? 9 : 0) * root.uiScale
                                width: parent.width
                                uiScale: root.uiScale
                                showApp: false
                                item: modelData

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

                            // In an open group each entry is its own target,
                            // so you can clear the one you have read.
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.dismissed(modelData)
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
                    onClicked: {
                        if (group.stacked) root.toggle(group.modelData.app);
                        else root.dismissed(group.modelData.items[0]);
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
