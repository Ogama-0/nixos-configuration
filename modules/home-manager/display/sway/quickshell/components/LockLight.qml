import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Services.Mpris

// Quickshell-native lockscreen. Stays idle in the background (no WlSessionLock
// held) until `root.locked` is flipped true over IPC, at which point it grabs
// the session lock and shows a password prompt authenticated via
// /etc/pam.d/quickshell-lock (see host/personal/configuration.nix).
Scope {
    id: root

    property bool locked: false
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false

    onCurrentTextChanged: root.showFailure = false

    function tryUnlock() {
        if (root.currentText === "" || root.unlockInProgress) return
        root.unlockInProgress = true
        pam.start()
    }

    PamContext {
        id: pam
        configDirectory: "/etc/pam.d"
        config: "quickshell-lock"

        onPamMessage: {
            if (this.responseRequired) this.respond(root.currentText)
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.currentText = ""
                // Fade the lock surface out before actually releasing the
                // session lock, so unlocking doesn't hard-cut to the desktop.
                root.unlocking = true
                unlockFadeTimer.restart()
            } else {
                root.currentText = ""
                root.showFailure = true
            }
            root.unlockInProgress = false
        }
    }

    Timer {
        id: postUnlockRestart
        interval: 500
        repeat: false
        onTriggered: restartWidgets.running = true
    }

    property bool unlocking: false
    readonly property int fadeDuration: 350

    Timer {
        id: unlockFadeTimer
        interval: root.fadeDuration
        repeat: false
        onTriggered: {
            root.unlocking = false
            root.locked = false
            postUnlockRestart.restart()
        }
    }

    Process {
        id: restartWidgets
        command: [ "@systemctlBin@", "--user", "restart", "quickshell-widgets" ]
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.locked = true }
        function unlock(): void { root.locked = false }
    }

    property var currentTime: new Date()
    Timer {
        running: root.locked
        repeat: true
        interval: 1000
        triggeredOnStart: true
        onTriggered: root.currentTime = new Date()
    }

    property string tempText: "Paris  --°C"
    Process {
        id: weatherProc
        command: [
            "curl", "-s", "--max-time", "5",
            "https://api.open-meteo.com/v1/forecast?latitude=48.8566&longitude=2.3522&current=temperature_2m"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text)
                    root.tempText = "Paris  " + data.current.temperature_2m.toFixed(1) + "°C"
                } catch (e) {
                    root.tempText = "Paris  --°C"
                }
            }
        }
    }
    Timer {
        running: root.locked
        repeat: true
        interval: 10 * 60 * 1000
        triggeredOnStart: true
        onTriggered: weatherProc.running = true
    }

    property var activePlayer: {
        const list = Mpris.players.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].isPlaying) return list[i]
        }
        for (let i = 0; i < list.length; i++) {
            if (list[i].playbackState !== MprisPlaybackState.Stopped) return list[i]
        }
        return null
    }

    property real livePosition: 0
    Process {
        id: positionProc
        running: false
        command: ["playerctl", "position"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(this.text)
                if (!isNaN(v)) root.livePosition = v
            }
        }
    }
    Timer {
        interval: 1000
        running: root.locked && root.activePlayer !== null
        repeat: true
        triggeredOnStart: true
        onTriggered: positionProc.running = true
    }

    // Reusable frosted-glass panel: clones+blurs the slice of the wallpaper
    // sitting behind it (rather than just a flat translucent rectangle) so
    // widgets read as real glass over the artwork, matching the reference
    // lockscreen designs.
    component GlassPanel: Item {
        id: panel

        property url bgSource: ""
        property real bgWidth: 0
        property real bgHeight: 0
        property alias radius: mask.radius
        property alias tint: tintRect.color
        property bool showBorder: true
        // 0..1 - lets the blur build up/ease down instead of snapping to full
        // strength, e.g. bound to the surface's fade-in/out progress.
        property real blurAmount: 1
        default property alias content: contentItem.data

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
        }

        Rectangle {
            id: mask
            anchors.fill: parent
            radius: 28
            visible: false
            layer.enabled: true
        }

        Image {
            source: panel.bgSource
            x: -panel.x
            y: -panel.y
            width: panel.bgWidth
            height: panel.bgHeight
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: panel.blurAmount
                blurMax: 48
            }
        }

        Rectangle {
            id: tintRect
            anchors.fill: parent
            radius: mask.radius
            color: "#3D000000"
            border.color: "#40FFFFFF"
            border.width: panel.showBorder ? 1 : 0
        }

        Item {
            id: contentItem
            anchors.fill: parent
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: root.locked

        WlSessionLockSurface {
            id: surface
            color: "@lockBg@"

            // Fades the whole surface in on lock and out on a successful
            // unlock (root.unlocking), instead of a hard cut.
            Item {
                id: content
                anchors.fill: parent
                opacity: 0

                Behavior on opacity {
                    NumberAnimation { duration: root.fadeDuration; easing.type: Easing.InOutQuad }
                }

                Component.onCompleted: content.opacity = 1

                Connections {
                    target: root
                    function onUnlockingChanged() {
                        if (root.unlocking) content.opacity = 0
                    }
                }

            Image {
                id: bg
                anchors.fill: parent
                source: "file://@lockscreenImage@"
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: surface.width
                sourceSize.height: surface.height
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#5C000000" }
                    GradientStop { position: 0.32; color: "#00000000" }
                    GradientStop { position: 0.7; color: "#00000000" }
                    GradientStop { position: 1.0; color: "#7A000000" }
                }
            }

            // A little bit of whimsy for the snowy wallpaper.
            ParticleSystem {
                id: snowSystem
                running: root.locked
            }

            Emitter {
                system: snowSystem
                anchors.fill: parent
                emitRate: 28
                lifeSpan: 13000
                lifeSpanVariation: 5000
                size: 7
                sizeVariation: 5
                endSize: 4
                velocity: PointDirection { y: 55; yVariation: 25; x: 0; xVariation: 15 }
            }

            Wander {
                system: snowSystem
                xVariance: 20
                pace: 50
            }

            ImageParticle {
                system: snowSystem
                source: "qrc:///particleresources/glowdot.png"
                color: "#FFFFFFFF"
                colorVariation: 0.05
                alpha: 0.7
                alphaVariation: 0.25
                entryEffect: ImageParticle.Fade
            }

            ColumnLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 140
                spacing: 6

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(root.currentTime, "HH:mm")
                    color: "#FFFFFFFF"
                    font.pixelSize: 124
                    font.weight: Font.Light
                    font.letterSpacing: -2

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#99000000"
                        shadowBlur: 0.8
                        shadowVerticalOffset: 4
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(root.currentTime, "dddd · d MMMM").toUpperCase()
                    color: "#E6FFFFFF"
                    font.pixelSize: 19
                    font.weight: Font.Medium
                    font.letterSpacing: 3

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#99000000"
                        shadowBlur: 0.6
                        shadowVerticalOffset: 2
                    }
                }
            }

            GlassPanel {
                id: tempPill
                bgSource: bg.source
                bgWidth: surface.width
                bgHeight: surface.height
                radius: 22
                showBorder: false
                blurAmount: content.opacity

                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 32
                width: tempRow.implicitWidth + 32
                height: 44

                RowLayout {
                    id: tempRow
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        text: root.tempText
                        color: "#FFFFFFFF"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                }
            }

            GlassPanel {
                id: musicCard
                bgSource: bg.source
                bgWidth: surface.width
                bgHeight: surface.height
                radius: 26
                blurAmount: content.opacity

                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 32
                width: 340
                height: 84

                visible: root.activePlayer !== null
                opacity: visible ? content.opacity : 0
                Behavior on opacity { NumberAnimation { duration: 250 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        radius: 14
                        color: "#33FFFFFF"
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: root.activePlayer ? (root.activePlayer.trackArtUrl || "") : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.activePlayer ? root.activePlayer.trackTitle : ""
                            color: "#FFFFFFFF"
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.activePlayer ? root.activePlayer.trackArtist : ""
                            color: "#CCFFFFFF"
                            font.pixelSize: 12
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            Layout.preferredHeight: 3

                            Rectangle {
                                anchors.fill: parent
                                radius: 1.5
                                color: "#33FFFFFF"
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                radius: 1.5
                                color: "#FFFFFFFF"
                                width: (root.activePlayer && root.activePlayer.length > 0)
                                    ? parent.width * Math.max(0, Math.min(1, root.livePosition / root.activePlayer.length))
                                    : 0
                            }
                        }
                    }

                    Text {
                        text: root.activePlayer && root.activePlayer.isPlaying ? "❚❚" : "▶"
                        color: "#FFFFFFFF"
                        font.pixelSize: 14

                        MouseArea {
                            anchors.centerIn: parent
                            width: 36
                            height: 36
                            enabled: root.activePlayer && root.activePlayer.canTogglePlaying
                            onClicked: root.activePlayer.togglePlaying()
                        }
                    }
                }
            }

            GlassPanel {
                id: passPanel
                bgSource: bg.source
                bgWidth: surface.width
                bgHeight: surface.height
                radius: 28
                tint: root.showFailure ? "#4DB33333" : "#3D000000"
                showBorder: false
                blurAmount: content.opacity

                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 64
                width: 340
                height: 56

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    spacing: 12

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TextInput {
                            id: passwordField
                            anchors.fill: parent
                            color: "transparent"
                            selectionColor: "transparent"
                            selectedTextColor: "transparent"
                            cursorVisible: false
                            // Qt's TextInput forces cursorVisible back to
                            // true internally on every focus-in
                            // (ItemActiveFocusHasChanged), silently breaking
                            // the plain binding above - reassert it every
                            // time that happens instead.
                            onCursorVisibleChanged: if (cursorVisible) cursorVisible = false
                            font.pixelSize: 18
                            echoMode: TextInput.Password
                            enabled: !root.unlockInProgress
                            focus: true

                            // Hides the I-beam mouse cursor over the field -
                            // HoverHandler tracks hover without consuming
                            // press events, unlike a MouseArea.
                            HoverHandler {
                                cursorShape: Qt.ArrowCursor
                            }

                            onTextChanged: root.currentText = text
                            onAccepted: root.tryUnlock()

                            Connections {
                                target: root
                                function onLockedChanged() {
                                    if (root.locked) {
                                        passwordField.text = ""
                                        passwordField.forceActiveFocus()
                                    }
                                }
                            }

                            // Clears the failed password instead of leaving
                            // it sitting in the field. Deliberately local to
                            // passwordField's own scope, not wired from
                            // PamContext up at the top of the file -
                            // reaching this id from that far outside the
                            // GlassPanel it's declared in throws "passwordField
                            // is not defined" at runtime (confirmed via
                            // quickshell's logs).
                            Connections {
                                target: root
                                function onShowFailureChanged() {
                                    if (root.showFailure) passwordField.text = ""
                                }
                            }
                        }

                        // Dots fade+pop in one at a time as you type, instead
                        // of the raw echo-mode glyphs appearing instantly.
                        Row {
                            anchors.centerIn: parent
                            spacing: 10

                            Repeater {
                                model: root.currentText.length

                                delegate: Rectangle {
                                    id: dot
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    color: "#FFFFFFFF"
                                    opacity: 0
                                    y: -12
                                    rotation: (Math.random() - 0.5) * 50
                                    transformOrigin: Item.Center

                                    // Randomized per-instance so dots never
                                    // move in lockstep with each other.
                                    property int fallDuration: 260 + Math.random() * 260

                                    Behavior on opacity {
                                        NumberAnimation { duration: dot.fallDuration; easing.type: Easing.OutQuad }
                                    }
                                    Behavior on y {
                                        NumberAnimation { duration: dot.fallDuration; easing.type: Easing.OutBack }
                                    }

                                    Component.onCompleted: {
                                        opacity = 1
                                        y = 0
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: root.unlockInProgress
                        text: "…"
                        color: "#CCFFFFFF"
                        font.pixelSize: 18
                    }
                }
            }

            property real passPanelBaseX: 0

            SequentialAnimation {
                id: shakeAnim
                loops: 1
                ScriptAction { script: content.passPanelBaseX = passPanel.x }
                NumberAnimation { target: passPanel; property: "x"; to: content.passPanelBaseX - 10; duration: 45 }
                NumberAnimation { target: passPanel; property: "x"; to: content.passPanelBaseX + 10; duration: 45 }
                NumberAnimation { target: passPanel; property: "x"; to: content.passPanelBaseX - 6; duration: 45 }
                NumberAnimation { target: passPanel; property: "x"; to: content.passPanelBaseX; duration: 45 }
            }

            Connections {
                target: root
                function onShowFailureChanged() {
                    if (root.showFailure) shakeAnim.restart()
                }
            }

            // passwordField only lives inside this surface's scope, not at
            // the top-level Scope PamContext runs in (per-screen
            // WlSessionLockSurface is its own id scope - referencing
            // passwordField directly from PamContext.onCompleted throws a
            // ReferenceError and aborts that handler, which is also why
            // unlockInProgress could get stuck true). Watching
            // unlockInProgress drop back to false here - from the right
            // scope, and after the field is actually re-enabled - clears
            // the failed password and hands focus back for a retry.
            Connections {
                target: root
                function onUnlockInProgressChanged() {
                    if (!root.unlockInProgress && root.showFailure) {
                        passwordField.text = ""
                        passwordField.forceActiveFocus()
                    }
                }
            }

            Text {
                anchors.top: passPanel.bottom
                anchors.topMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.showFailure
                text: "Incorrect password"
                color: "#FFE0A0A0"
                font.pixelSize: 13

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#99000000"
                    shadowBlur: 0.5
                }
            }
            }
        }
    }
}
