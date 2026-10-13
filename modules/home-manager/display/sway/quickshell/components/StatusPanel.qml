pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as Components

PanelWindow {
    id: win

    // ---------------- geometry ----------------
    //
    // Every size lives here so the widget can be scaled by editing this block
    // alone. The derived values below are what keep the spine honest: band n
    // must sit exactly on row n, and that is arithmetic, not luck.

    readonly property int sq: 28           // idle square
    readonly property int pillW: 232
    readonly property int pillH: 48
    readonly property int panelW: 376
    readonly property int rowHeight: 32
    readonly property int headerH: 22      // verdict line
    readonly property int rowsPad: 12      // gap between verdict and first row
    readonly property int footerH: 32      // divider + host figures
    readonly property int spineW: 6

    readonly property int padTop: 13
    readonly property int padBottom: 12
    readonly property int padLeft: 11
    readonly property int padRight: 16
    readonly property int gap: 13          // spine to content

    readonly property int serviceCount: Math.max(1, statusModel.services.length)

    readonly property int panelH:
        padTop + headerH + rowsPad + rowHeight * serviceCount + footerH + padBottom

    anchors {
        bottom: true
        left: true
    }
    margins {
        bottom: 24
        left: 24
    }

    implicitWidth: panelW + 18
    // Derived, not fixed: the panel is bottom-anchored inside this window, so
    // a constant height silently clips it once the service list grows past
    // whatever that constant allowed.
    implicitHeight: panelH + 24
    color: "transparent"

    WlrLayershell.namespace: "status-widget"
    // Bottom, not Top: this is an ambient desktop widget and must never
    // occlude application windows. Not Background either - Wallpaper.qml
    // already occupies that layer, and z-order between two Background
    // surfaces is creation-order dependent, so the widget could end up behind
    // the wallpaper and vanish.
    WlrLayershell.layer: WlrLayer.Bottom
    exclusionMode: ExclusionMode.Ignore
    focusable: false

    // Only the widget's own rounded rectangle accepts the pointer. Region
    // follows the item's geometry, so this tracks the growth automatically.
    mask: Region {
        item: shell
        radius: shell.radius
    }

    Components.StatusModel {
        // Deliberately not `id: model` - that collides with Repeater's own
        // `model` property, making `model: model.services` resolve against the
        // Repeater rather than this component.
        id: statusModel
    }

    // 0 = square, 1 = summary pill, 2 = full panel. Driven by the hover
    // handlers below: the square opens the pill, the pill opens the panel.
    property int stage: 0

    Rectangle {
        id: shell

        anchors.left: parent.left
        anchors.bottom: parent.bottom

        width: win.stage === 0 ? win.sq : win.stage === 1 ? win.pillW : win.panelW
        height: win.stage === 0 ? win.sq : win.stage === 1 ? win.pillH : win.panelH
        radius: win.stage === 0 ? 9 : win.stage === 1 ? 16 : 20

        // At idle the surface drops away entirely and the spine *is* the
        // object, so the verdict colour reads with nothing around it.
        color: win.stage === 0 ? "transparent" : "@panelBg@"
        border.color: win.stage === 0 ? "transparent" : "@panelBorder@"
        border.width: 1

        // The detail fades in while the height is still growing; without
        // clipping the rows would spill outside the pill mid-transition.
        // Clipping turns that into a reveal instead.
        clip: true

        Behavior on width {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 210; easing.type: Easing.OutCubic }
        }
        Behavior on radius {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }

        // Whole-widget hover: leaving by any edge collapses back to the square.
        HoverHandler {
            id: shellHover
            onHoveredChanged: if (!hovered) win.stage = 0
        }

        // ---------------- content area ----------------
        //
        // Deliberately not a Row/Column. Positioners size themselves from
        // their children during a polish pass, and a Repeater whose JS-array
        // model is reassigned (which happens on every poll here) can rebuild
        // its delegates without that pass re-running - leaving a Column
        // reporting its padding as its full height and every child stacked at
        // y=0. Explicit y arithmetic cannot fail that way, and it makes the
        // band/row alignment true by construction rather than by coincidence.
        Item {
            id: contentArea

            anchors.fill: parent
            anchors.topMargin: win.stage === 0 ? 0 : win.padTop
            anchors.bottomMargin: win.stage === 0 ? 0 : win.padBottom
            anchors.leftMargin: win.stage === 0 ? 0 : win.padLeft
            anchors.rightMargin: win.stage === 0 ? 0 : win.padRight

            // ---- the health spine ----
            // One band per service, fixed order. Collapsed it is the idle
            // square; expanded it is this rail, with every band aligned to its
            // own row. Positions never move between stages, so a red band in
            // the square already says which service broke.
            Item {
                id: spineBox

                x: 0
                y: 0
                width: win.stage === 0 ? parent.width : win.spineW
                height: parent.height

                HoverHandler {
                    onHoveredChanged: if (hovered && win.stage === 0) win.stage = 1
                }

                // At stage 2 the bands start below the verdict line and its
                // padding, so band n lands on row n; at the smaller stages
                // they simply fill the available height.
                readonly property real bandTop:
                    win.stage === 2 ? win.headerH + win.rowsPad : 0
                readonly property real bandH:
                    win.stage === 2
                        ? win.rowHeight
                        : height / win.serviceCount

                Repeater {
                    model: statusModel.services

                    Rectangle {
                        id: band
                        required property var modelData
                        required property int index

                        // Inset rather than a gap between equal bands: a gap
                        // would shift every band's centre off its row's centre,
                        // whereas a symmetric inset leaves it exactly on it.
                        readonly property int inset: win.stage === 0 ? 0 : 1

                        x: 0
                        y: spineBox.bandTop + index * spineBox.bandH + inset
                        width: spineBox.width
                        height: Math.max(1, spineBox.bandH - inset * 2)

                        // At idle the bands butt together into a single square,
                        // so only the outer corners round.
                        radius: win.stage === 0 ? 0 : 3
                        topLeftRadius: win.stage === 0 && band.index === 0 ? 9 : radius
                        topRightRadius: win.stage === 0 && band.index === 0 ? 9 : radius
                        bottomLeftRadius:
                            win.stage === 0 && band.index === win.serviceCount - 1 ? 9 : radius
                        bottomRightRadius:
                            win.stage === 0 && band.index === win.serviceCount - 1 ? 9 : radius

                        color: band.modelData.state === "up" ? "@upColor@"
                             : band.modelData.state === "degraded" ? "@degradedColor@"
                             : band.modelData.state === "down" ? "@downColor@"
                             : "@unknownColor@"
                        opacity: statusModel.online ? 1.0 : 0.55
                    }
                }
            }

            // ---- content column ----
            Item {
                id: contentBox

                x: win.spineW + win.gap
                y: 0
                width: Math.max(0, parent.width - x)
                height: parent.height
                visible: win.stage !== 0

                HoverHandler {
                    onHoveredChanged: if (hovered && win.stage === 1) win.stage = 2
                }

                // Verdict line. Stays mounted in stage 2 as the header, which
                // is what makes the pill and the panel feel like one object
                // rather than a swap.
                Item {
                    id: header
                    x: 0
                    y: 0
                    width: parent.width
                    height: win.headerH

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: statusModel.verdictText
                        color: statusModel.online ? "@nameColor@" : "@mutedColor@"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: statusModel.verdictCount
                        color: "@mutedColor@"
                        font.pixelSize: 13
                        font.features: ({ "tnum": 1 })
                    }
                }

                // ---- per-service rows ----
                Item {
                    id: rowsBox
                    x: 0
                    y: win.headerH + win.rowsPad
                    width: parent.width
                    height: win.rowHeight * win.serviceCount

                    visible: opacity > 0
                    opacity: win.stage === 2 ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                    }

                    Repeater {
                        model: statusModel.services

                        Item {
                            id: row
                            required property var modelData
                            required property int index

                            x: 0
                            y: index * win.rowHeight
                            width: rowsBox.width
                            height: win.rowHeight

                            property bool showResources:
                                rowHover.hovered && statusModel.online
                                && (modelData.cpu !== "" || modelData.ram !== "")

                            HoverHandler { id: rowHover }

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: -4
                                anchors.rightMargin: -6
                                anchors.topMargin: 1
                                anchors.bottomMargin: 1
                                radius: 6
                                color: rowHover.hovered ? "@panelBorder@" : "transparent"
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 148
                                elide: Text.ElideRight
                                text: row.modelData.label
                                color: row.modelData.state === "down" ? "@downColor@"
                                     : row.modelData.state === "unknown" ? "@mutedColor@"
                                     : "@nameColor@"
                                font.pixelSize: 14
                            }

                            Components.Sparkline {
                                anchors.right: msText.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !row.showResources && row.modelData.history.length > 0
                                history: row.modelData.history
                                lineColor: row.modelData.state === "degraded"
                                    ? "@degradedColor@" : "@upColor@"
                            }

                            Text {
                                id: msText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !row.showResources
                                text: row.modelData.state === "unknown" ? "—"
                                    : row.modelData.state === "down" ? "no reply"
                                    : row.modelData.ms + " ms"
                                color: "@mutedColor@"
                                font.pixelSize: 13
                                font.features: ({ "tnum": 1 })
                            }

                            // The second layer, kept out of the way until the
                            // row is actually asked about.
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: row.showResources
                                text: row.modelData.cpu + "  " + row.modelData.ram
                                color: "@mutedColor@"
                                font.pixelSize: 13
                                font.features: ({ "tnum": 1 })
                            }
                        }
                    }
                }

                // ---- host footer ----
                Item {
                    id: footer
                    x: 0
                    y: parent.height - win.footerH
                    width: parent.width
                    height: win.footerH

                    visible: opacity > 0
                    opacity: win.stage === 2 ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 11
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: "@panelBorder@"
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        spacing: 16

                        Text {
                            text: "load " + statusModel.hostLoad
                            color: "@mutedColor@"
                            font.pixelSize: 13
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            text: "ram " + statusModel.hostRam
                            color: "@mutedColor@"
                            font.pixelSize: 13
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            text: "disk " + statusModel.hostDisk
                            color: "@mutedColor@"
                            font.pixelSize: 13
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }
}
