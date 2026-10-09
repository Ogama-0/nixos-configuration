pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as Components

PanelWindow {
    id: win

    // Stage 2 is the largest extent; the window is sized to it and the widget
    // is drawn in its bottom-left. The mask below keeps input confined to the
    // widget itself so the rest of this window is click-through.
    readonly property int rowHeight: 26

    anchors {
        bottom: true
        left: true
    }
    margins {
        bottom: 22
        left: 22
    }

    implicitWidth: 320
    implicitHeight: 380
    color: "transparent"

    WlrLayershell.namespace: "status-widget"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Ignore
    focusable: false

    // Only the widget's own rounded rectangle accepts the pointer. Region
    // follows the item's geometry, so this tracks the growth automatically
    // with no manual recalculation.
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

    // 0 = square, 1 = summary pill, 2 = full panel.
    property int stage: 2

    readonly property int sq: 22
    readonly property int pillW: 186
    readonly property int pillH: 40
    readonly property int panelW: 302
    // 11 top pad + 18 verdict + 10 rows pad + rows + 27 footer + 10 bottom pad.
    // Math.max guards the moment before the first poll returns, when the
    // service list is empty and the panel would otherwise collapse.
    readonly property int panelH:
        11 + 18 + 10
        + rowHeight * Math.max(1, statusModel.services.length)
        + 27 + 10

    Rectangle {
        id: shell

        anchors.left: parent.left
        anchors.bottom: parent.bottom

        width: win.stage === 0 ? win.sq : win.stage === 1 ? win.pillW : win.panelW
        height: win.stage === 0 ? win.sq : win.stage === 1 ? win.pillH : win.panelH
        radius: win.stage === 0 ? 7 : win.stage === 1 ? 13 : 16

        // At idle the surface drops away entirely and the spine *is* the
        // object, so the verdict colour reads with nothing around it.
        color: win.stage === 0 ? "transparent" : "@panelBg@"
        border.color: win.stage === 0 ? "transparent" : "@panelBorder@"
        border.width: 1

        Row {
            anchors.fill: parent
            anchors.margins: win.stage === 0 ? 0 : 1
            anchors.leftMargin: win.stage === 0 ? 0 : 9
            anchors.rightMargin: win.stage === 0 ? 0 : 13
            anchors.topMargin: win.stage === 0 ? 0 : 11
            anchors.bottomMargin: win.stage === 0 ? 0 : 10
            spacing: win.stage === 0 ? 0 : 11

            // ---- the health spine ----
            // One band per service, fixed order. Collapsed it is the idle
            // square; expanded it is this rail, with every band aligned to its
            // own row. Positions never move between stages, so a red band in
            // the square already says which service broke.
            Item {
                id: spineBox
                width: win.stage === 0 ? win.sq : 5
                height: parent.height

                // At stage 2 the spine must span exactly the rows block, not
                // the whole panel - otherwise the bands drift out of line with
                // their rows and the spine stops meaning anything. 28 = the
                // 18px verdict line plus the rows' 10px top padding; 27 = the
                // footer.
                readonly property int topInset: win.stage === 2 ? 28 : 0
                readonly property int bottomInset: win.stage === 2 ? 27 : 0

                readonly property int count:
                    Math.max(1, statusModel.services.length)
                readonly property real bandH:
                    (height - topInset - bottomInset) / count

                Column {
                    id: spineColumn
                    y: spineBox.topInset
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: statusModel.services

                        Item {
                            id: band
                            required property var modelData
                            required property int index

                            width: spineBox.width
                            height: spineBox.bandH

                            Rectangle {
                                anchors.fill: parent
                                // Inset rather than Column spacing: equal bands
                                // separated by gaps would shift every band's
                                // centre off its row's centre. An inset keeps
                                // band n centred exactly on row n.
                                anchors.topMargin: win.stage === 0 ? 0 : 1
                                anchors.bottomMargin: win.stage === 0 ? 0 : 1

                                // At idle the bands butt together into a single
                                // square, so only the outer corners round.
                                radius: win.stage === 0 ? 0 : 2
                                topLeftRadius:
                                    win.stage === 0 && band.index === 0 ? 7 : radius
                                topRightRadius:
                                    win.stage === 0 && band.index === 0 ? 7 : radius
                                bottomLeftRadius:
                                    win.stage === 0 && band.index === spineBox.count - 1 ? 7 : radius
                                bottomRightRadius:
                                    win.stage === 0 && band.index === spineBox.count - 1 ? 7 : radius

                                color: band.modelData.state === "up" ? "@upColor@"
                                     : band.modelData.state === "degraded" ? "@degradedColor@"
                                     : band.modelData.state === "down" ? "@downColor@"
                                     : "@unknownColor@"
                                opacity: statusModel.online ? 1.0 : 0.55
                            }
                        }
                    }
                }
            }

            // ---- content column ----
            Column {
                id: contentCol
                width: parent.width - spineBox.width - parent.spacing
                visible: win.stage !== 0
                spacing: 0

                // Verdict line. Stays mounted in stage 2 as the header, which
                // is what makes the pill and the panel feel like one object
                // rather than a swap.
                Item {
                    width: parent.width
                    height: 18

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: statusModel.verdictText
                        color: statusModel.online ? "@nameColor@" : "@mutedColor@"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: statusModel.verdictCount
                        color: "@mutedColor@"
                        font.pixelSize: 11
                        font.features: ({ "tnum": 1 })
                    }
                }

                // ---- per-service rows ----
                Column {
                    id: rowsColumn
                    width: parent.width
                    visible: win.stage === 2
                    spacing: 0
                    topPadding: 10

                    Repeater {
                        model: statusModel.services

                        Item {
                            id: row
                            required property var modelData

                            width: rowsColumn.width
                            height: win.rowHeight

                            property bool showResources:
                                rowHover.hovered && statusModel.online
                                && (modelData.cpu !== "" || modelData.ram !== "")

                            HoverHandler { id: rowHover }

                            Rectangle {
                                anchors.fill: parent
                                anchors.rightMargin: -4
                                radius: 5
                                color: rowHover.hovered ? "@panelBorder@" : "transparent"
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 108
                                elide: Text.ElideRight
                                text: row.modelData.label
                                color: row.modelData.state === "down" ? "@downColor@"
                                     : row.modelData.state === "unknown" ? "@mutedColor@"
                                     : "@nameColor@"
                                font.pixelSize: 12
                            }

                            Components.Sparkline {
                                anchors.right: msText.left
                                anchors.rightMargin: 8
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
                                font.pixelSize: 11
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
                                font.pixelSize: 11
                                font.features: ({ "tnum": 1 })
                            }
                        }
                    }
                }

                // ---- host footer ----
                Item {
                    width: parent.width
                    height: 27
                    visible: win.stage === 2

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 9
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: "@panelBorder@"
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.bottom: parent.bottom
                        spacing: 14

                        Text {
                            text: "load " + statusModel.hostLoad
                            color: "@mutedColor@"
                            font.pixelSize: 11
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            text: "ram " + statusModel.hostRam
                            color: "@mutedColor@"
                            font.pixelSize: 11
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            text: "disk " + statusModel.hostDisk
                            color: "@mutedColor@"
                            font.pixelSize: 11
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }
}
