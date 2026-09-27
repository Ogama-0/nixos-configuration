import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: root

    property var imagePaths: []
    property bool pickerOpen: false

    property int activeLayer: 0
    property string pathA: ""
    property string pathB: ""

    // 0 = fade, 1 = wipe, 2 = iris (expanding circle)
    property int transitionType: 0
    property bool wipeVertical: false
    property real originX: 0.5
    property real originY: 0.5
    property real transitionProgress: 1.0

    function currentPath() {
        return root.activeLayer === 0 ? root.pathA : root.pathB
    }

    function beginTransition(next) {
        root.transitionType = Math.floor(Math.random() * 3)
        root.wipeVertical = Math.random() < 0.5
        root.originX = 0.15 + Math.random() * 0.7
        root.originY = 0.15 + Math.random() * 0.7

        if (root.activeLayer === 0) {
            root.pathB = next
            root.activeLayer = 1
        } else {
            root.pathA = next
            root.activeLayer = 0
        }
        root.transitionProgress = 0.0
        transitionAnim.restart()
    }

    function pickNext() {
        if (root.imagePaths.length === 0) return

        let candidates = root.imagePaths
        if (candidates.length > 1) {
            const current = root.currentPath()
            candidates = candidates.filter(p => p !== current)
        }
        root.beginTransition(candidates[Math.floor(Math.random() * candidates.length)])
    }

    function pickSpecific(path) {
        root.pickerOpen = false
        if (!path || path === root.currentPath()) return
        root.beginTransition(path)
    }

    Process {
        id: listProc
        running: true
        command: [
            "bash", "-c",
            "find \"$HOME/nixos-configuration/assets/wallpaper\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.imagePaths = this.text.split("\n").map(s => s.trim()).filter(s => s.length > 0)
                if (root.pathA === "" && root.imagePaths.length > 0) {
                    root.pathA = root.imagePaths[Math.floor(Math.random() * root.imagePaths.length)]
                    root.activeLayer = 0
                    root.transitionProgress = 1.0
                }
            }
        }
    }

    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: root.pickNext()
    }

    IpcHandler {
        target: "wallpaper"
        function next(): void {
            root.pickNext()
        }
        function togglePicker(): void {
            root.pickerOpen = !root.pickerOpen
        }
    }

    NumberAnimation {
        id: transitionAnim
        target: root
        property: "transitionProgress"
        from: 0.0
        to: 1.0
        duration: 1200
        easing.type: Easing.InOutCubic
    }

    PanelWindow {
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.namespace: "wallpaper-bg"
        WlrLayershell.layer: WlrLayer.Background
        exclusionMode: ExclusionMode.Ignore
        focusable: false
        mask: Region {}
        color: "#000000"

        Item {
            anchors.fill: parent
            clip: true

            Item {
                id: layerA
                anchors.fill: parent

                readonly property bool incoming: root.activeLayer === 0
                readonly property real p: root.transitionProgress

                z: incoming ? 2 : 1
                visible: incoming || p < 1.0
                opacity: root.transitionType === 0 ? (incoming ? p : 1.0 - p) : 1.0

                layer.enabled: root.transitionType !== 0 && incoming && p < 1.0
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: maskA
                    maskThresholdMin: 0.0
                    maskSpreadAtMin: 0.0
                }

                Item {
                    id: maskA
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true

                    Rectangle {
                        color: "white"

                        readonly property real p: layerA.p
                        readonly property real cx: root.originX * parent.width
                        readonly property real cy: root.originY * parent.height
                        readonly property real maxR: Math.sqrt(
                            Math.max(cx, parent.width - cx) * Math.max(cx, parent.width - cx) +
                            Math.max(cy, parent.height - cy) * Math.max(cy, parent.height - cy))

                        width: root.transitionType === 1
                            ? (root.wipeVertical ? parent.width : p * parent.width)
                            : p * maxR * 2
                        height: root.transitionType === 1
                            ? (root.wipeVertical ? p * parent.height : parent.height)
                            : p * maxR * 2
                        x: root.transitionType === 1 ? 0 : cx - width / 2
                        y: root.transitionType === 1
                            ? (root.wipeVertical ? parent.height - height : 0)
                            : cy - height / 2
                        radius: root.transitionType === 2 ? width / 2 : 0
                    }
                }

                Image {
                    anchors.fill: parent
                    source: root.pathA ? "file://" + root.pathA : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: parent.width
                    sourceSize.height: parent.height
                }
            }

            Item {
                id: layerB
                anchors.fill: parent

                readonly property bool incoming: root.activeLayer === 1
                readonly property real p: root.transitionProgress

                z: incoming ? 2 : 1
                visible: incoming || p < 1.0
                opacity: root.transitionType === 0 ? (incoming ? p : 1.0 - p) : 1.0

                layer.enabled: root.transitionType !== 0 && incoming && p < 1.0
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: maskB
                    maskThresholdMin: 0.0
                    maskSpreadAtMin: 0.0
                }

                Item {
                    id: maskB
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true

                    Rectangle {
                        color: "white"

                        readonly property real p: layerB.p
                        readonly property real cx: root.originX * parent.width
                        readonly property real cy: root.originY * parent.height
                        readonly property real maxR: Math.sqrt(
                            Math.max(cx, parent.width - cx) * Math.max(cx, parent.width - cx) +
                            Math.max(cy, parent.height - cy) * Math.max(cy, parent.height - cy))

                        width: root.transitionType === 1
                            ? (root.wipeVertical ? parent.width : p * parent.width)
                            : p * maxR * 2
                        height: root.transitionType === 1
                            ? (root.wipeVertical ? p * parent.height : parent.height)
                            : p * maxR * 2
                        x: root.transitionType === 1 ? 0 : cx - width / 2
                        y: root.transitionType === 1
                            ? (root.wipeVertical ? parent.height - height : 0)
                            : cy - height / 2
                        radius: root.transitionType === 2 ? width / 2 : 0
                    }
                }

                Image {
                    anchors.fill: parent
                    source: root.pathB ? "file://" + root.pathB : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: parent.width
                    sourceSize.height: parent.height
                }
            }
        }
    }

    PanelWindow {
        id: pickerWindow
        visible: root.pickerOpen

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.namespace: "wallpaper-picker"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        focusable: true
        color: "@cardBg@"

        MouseArea {
            anchors.fill: parent
            onClicked: root.pickerOpen = false
        }

        GridView {
            id: grid
            anchors.centerIn: parent
            width: Math.min(parent.width - 160, 900)
            height: Math.min(parent.height - 160, 600)
            cellWidth: 220
            cellHeight: 150
            model: root.imagePaths
            clip: true
            focus: true

            Keys.onTabPressed: grid.currentIndex = grid.count > 0 ? (grid.currentIndex + 1) % grid.count : -1
            Keys.onBacktabPressed: grid.currentIndex = grid.count > 0 ? (grid.currentIndex - 1 + grid.count) % grid.count : -1
            Keys.onReturnPressed: if (grid.currentIndex >= 0) root.pickSpecific(root.imagePaths[grid.currentIndex])
            Keys.onEnterPressed: if (grid.currentIndex >= 0) root.pickSpecific(root.imagePaths[grid.currentIndex])
            Keys.onEscapePressed: root.pickerOpen = false

            delegate: Item {
                required property string modelData
                required property int index

                width: 200
                height: 130

                Rectangle {
                    id: thumbBg
                    anchors.fill: parent
                    radius: 16
                    color: "@cardBorder@"
                    border.width: 3
                    border.color: index === grid.currentIndex
                        ? "@clockColor@"
                        : (modelData === root.currentPath() ? "@tempColor@" : "@cardBorder@")
                }

                Rectangle {
                    id: thumbMask
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: 13
                    visible: false
                    layer.enabled: true
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: 3
                    source: "file://" + modelData
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: thumbMask
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        grid.currentIndex = index
                        root.pickSpecific(modelData)
                    }
                }
            }
        }
    }

    onPickerOpenChanged: {
        if (root.pickerOpen) {
            const idx = root.imagePaths.indexOf(root.currentPath())
            grid.currentIndex = idx >= 0 ? idx : 0
        }
    }
}
