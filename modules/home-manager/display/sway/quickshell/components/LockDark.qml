import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Services.Mpris

// Dark-mode lockscreen - Zaun/Jinx DA built around the full-bleed artwork
// at assets/lockscreen/dark-lockscreen-arcane-jinx.jpeg (wired in via
// @lockscreenImage@, see ../default.nix). Deliberately not a recolor of
// LockLight.qml's glass/snow treatment: flat angular stencil panels with
// neon edge-glow instead of frosted glass (matches the "no liquid-glass
// look" language already established by LaserBar/ClockModule), content
// pushed into the calm top-left of the photo instead of centered, and
// Orbitron for the clock to tie back to the bar's own clock module.
Scope {
    id: root

    property bool locked: false
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false

    // Source palette, pulled straight from the artwork rather than a
    // generic neon-green/near-black default - magenta is Jinx's color,
    // cyan is the chemtech/Zaun glow, amber is the explosion in the frame.
    readonly property color accentMagenta: "#FF2E86"
    readonly property color accentCyan: "#33E6D8"
    readonly property color accentAmber: "#FFB23D"
    readonly property color paperWhite: "#F3F0EA"
    readonly property color smokeLavender: "#D6D1E6"

    onCurrentTextChanged: root.showFailure = false

    // QML has no built-in "take this color, override its alpha" helper
    // (Qt.rgba needs explicit r/g/b, not a color + alpha shortcut).
    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

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

    property string tempText: "Paris --°"
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
                    root.tempText = "Paris " + data.current.temperature_2m.toFixed(1) + "°"
                } catch (e) {
                    root.tempText = "Paris --°"
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

    // One signature motion for the whole screen: the clock flickers up
    // like a neon tube catching power, instead of fades/hovers scattered
    // across every element.
    property real clockFlicker: 0
    SequentialAnimation {
        id: flickerAnim
        ScriptAction { script: root.clockFlicker = 0 }
        NumberAnimation { target: root; property: "clockFlicker"; to: 1; duration: 60 }
        NumberAnimation { target: root; property: "clockFlicker"; to: 0.15; duration: 50 }
        NumberAnimation { target: root; property: "clockFlicker"; to: 1; duration: 90 }
        NumberAnimation { target: root; property: "clockFlicker"; to: 0.35; duration: 40 }
        NumberAnimation { target: root; property: "clockFlicker"; to: 1; duration: 220 }
    }

    // Flat angular placard: a stenciled hexagon (two chamfered corners)
    // with a neon-colored edge-glow, not a frosted/blurred glass card -
    // keeps the lockscreen in the same visual language as the bar's
    // sharp-edged, un-blurred panels (see ClockModule.qml/LaserBar.qml).
    // The glow is a tight, bright rim on the edge itself (small blur radius,
    // full alpha) rather than a soft halo bled onto the photo - brighter,
    // not bigger.
    component TagPanel: Item {
        id: panel

        property color accentColor: "#FF2E86"
        property color fill: "#E6140A18"
        property real cut: 14
        default property alias content: contentItem.data

        Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(panel.accentColor.r, panel.accentColor.g, panel.accentColor.b, 1.0)
                shadowBlur: 0.4
            }
            ShapePath {
                fillColor: panel.fill
                strokeColor: Qt.lighter(panel.accentColor, 1.25)
                strokeWidth: 3
                startX: panel.cut; startY: 0
                PathLine { x: panel.width; y: 0 }
                PathLine { x: panel.width; y: panel.height - panel.cut }
                PathLine { x: panel.width - panel.cut; y: panel.height }
                PathLine { x: 0; y: panel.height }
                PathLine { x: 0; y: panel.cut }
                PathLine { x: panel.cut; y: 0 }
            }
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

            Item {
                id: content
                anchors.fill: parent
                opacity: 0

                Behavior on opacity {
                    NumberAnimation { duration: root.fadeDuration; easing.type: Easing.InOutQuad }
                }

                Component.onCompleted: {
                    content.opacity = 1
                    flickerAnim.start()
                }

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

                // Keeps the top-left readout and the bottom placards legible
                // against the artwork without flattening the explosion/neon
                // in the middle of the frame, where the artwork should read
                // untouched.
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#73000000" }
                        GradientStop { position: 0.24; color: "#00000000" }
                        GradientStop { position: 0.66; color: "#00000000" }
                        GradientStop { position: 1.0; color: "#8C000000" }
                    }
                }

                // ── Readout: pushed right of the glowing enforcer-head/blade
                // on the far left edge, into the genuinely empty dark band
                // above the plank. Left-aligned rather than centered, like a
                // tag thrown up in the corner of the shot, not a dashboard -
                // just moved off the busiest edge of the frame.
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: Math.round(parent.width * 0.20)
                    anchors.topMargin: Math.round(parent.height * 0.08)
                    spacing: 4

                    Text {
                        id: clockText
                        text: Qt.formatDateTime(root.currentTime, "HH:mm")
                        color: root.paperWhite
                        font.family: "Orbitron"
                        font.pixelSize: 104
                        font.bold: true
                        font.letterSpacing: -2
                        opacity: root.clockFlicker

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: root.withAlpha(root.accentMagenta, 1.0)
                            shadowBlur: 0.5
                        }
                    }

                    Text {
                        text: Qt.formatDateTime(root.currentTime, "dddd, d MMMM")
                        color: root.smokeLavender
                        font.family: "Inter"
                        font.pixelSize: 18
                        font.weight: Font.Medium
                    }

                    Text {
                        Layout.topMargin: 2
                        text: root.tempText
                        color: root.smokeLavender
                        font.family: "Inter"
                        font.pixelSize: 15
                    }
                }

                // ── Now-playing ticket, tucked into the true top-right
                // corner - clear of the tower's lit windows/purple glow
                // that sit further in from the edge, and of the readout.
                TagPanel {
                    id: musicTicket
                    accentColor: root.accentCyan
                    fill: "#E60C2426"
                    cut: 12
                    visible: root.activePlayer !== null
                    opacity: visible ? content.opacity : 0
                    Behavior on opacity { NumberAnimation { duration: 250 } }

                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: Math.round(parent.height * 0.035)
                    anchors.rightMargin: Math.round(parent.width * 0.025)
                    width: 290
                    height: 76
                    // Not tilted like the password placard - the progress
                    // bar inside reads as broken/crooked when the whole
                    // panel is rotated, instead of as a thrown-on sticker.

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 13
                        anchors.leftMargin: 17
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 52
                            color: "#1AFFFFFF"
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
                                color: root.paperWhite
                                font.family: "Inter"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.activePlayer ? root.activePlayer.trackArtist : ""
                                color: root.smokeLavender
                                font.family: "Inter"
                                font.pixelSize: 12
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.topMargin: 5
                                Layout.preferredHeight: 3

                                Rectangle {
                                    anchors.fill: parent
                                    color: "#26FFFFFF"
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    color: root.accentCyan
                                    width: (root.activePlayer && root.activePlayer.length > 0)
                                        ? parent.width * Math.max(0, Math.min(1, root.livePosition / root.activePlayer.length))
                                        : 0
                                }
                            }
                        }

                        Text {
                            text: root.activePlayer && root.activePlayer.isPlaying ? "❚❚" : "▶"
                            color: root.paperWhite
                            font.pixelSize: 13

                            MouseArea {
                                anchors.centerIn: parent
                                width: 32
                                height: 32
                                enabled: root.activePlayer && root.activePlayer.canTogglePlaying
                                onClicked: root.activePlayer.togglePlaying()
                            }
                        }
                    }
                }

                // ── Password placard, bottom-left: a stenciled tag stuck
                // low in the frame, pulled in off the very edge and clear
                // of the glowing enforcer-head/blade above it and the
                // explosion over on the right.
                TagPanel {
                    id: passPanel
                    accentColor: root.showFailure ? root.accentAmber : root.accentMagenta
                    fill: root.showFailure ? "#E6241206" : "#E6240420"
                    cut: 16

                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: Math.round(parent.width * 0.09)
                    anchors.bottomMargin: Math.round(parent.height * 0.09)
                    width: 340
                    height: 58
                    rotation: -1.3

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 26
                        anchors.rightMargin: 22
                        spacing: 12

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.currentText.length === 0 && !root.unlockInProgress
                                text: "password"
                                color: root.withAlpha(root.smokeLavender, 0.65)
                                font.family: "Inter"
                                font.pixelSize: 15
                            }

                            TextInput {
                                id: passwordField
                                anchors.fill: parent
                                color: "transparent"
                                selectionColor: "transparent"
                                selectedTextColor: "transparent"
                                cursorVisible: false
                                // Qt's TextInput forces cursorVisible back
                                // to true internally on every focus-in
                                // (ItemActiveFocusHasChanged), silently
                                // breaking the plain binding above - reassert
                                // it every time that happens instead.
                                onCursorVisibleChanged: if (cursorVisible) cursorVisible = false
                                font.pixelSize: 18
                                echoMode: TextInput.Password
                                enabled: !root.unlockInProgress
                                focus: true

                                // Hides the I-beam mouse cursor over the
                                // field - HoverHandler tracks hover without
                                // consuming press events, unlike a MouseArea.
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

                                // Clears the failed password instead of
                                // leaving it sitting in the field. Deliberately
                                // local to passwordField's own scope, not
                                // wired from PamContext up at the top of the
                                // file - reaching this id from that far
                                // outside the TagPanel it's declared in
                                // throws "passwordField is not defined" at
                                // runtime (confirmed via quickshell's logs).
                                Connections {
                                    target: root
                                    function onShowFailureChanged() {
                                        if (root.showFailure) passwordField.text = ""
                                    }
                                }
                            }

                            // Drips of paint falling in as each character is
                            // typed, instead of the raw password glyphs.
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 9

                                Repeater {
                                    model: root.currentText.length

                                    delegate: Rectangle {
                                        id: dot
                                        width: 9
                                        height: 9
                                        radius: 4.5
                                        color: index % 2 === 0 ? root.accentMagenta : root.accentCyan
                                        opacity: 0
                                        y: -12
                                        rotation: (Math.random() - 0.5) * 50
                                        transformOrigin: Item.Center

                                        property int fallDuration: 260 + Math.random() * 260

                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            shadowEnabled: true
                                            shadowColor: Qt.rgba(dot.color.r, dot.color.g, dot.color.b, 0.9)
                                            shadowBlur: 0.8
                                        }

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
                            color: root.smokeLavender
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

                // passwordField only lives inside this surface's scope, not
                // at the top-level Scope PamContext runs in (per-screen
                // WlSessionLockSurface is its own id scope - referencing
                // passwordField directly from PamContext.onCompleted throws
                // a ReferenceError and aborts that handler, which is also
                // why unlockInProgress could get stuck true). Watching
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
                    anchors.left: passPanel.left
                    anchors.top: passPanel.bottom
                    anchors.topMargin: 10
                    visible: root.showFailure
                    text: "ACCESS DENIED"
                    color: root.accentAmber
                    font.family: "Orbitron"
                    font.pixelSize: 12
                    font.bold: true
                    font.letterSpacing: 1

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: root.withAlpha(root.accentAmber, 0.85)
                        shadowBlur: 0.9
                    }
                }
            }
        }
    }
}
