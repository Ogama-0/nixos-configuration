import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

// Light-mode greeter - the login-screen sibling of LockLight.qml, keeping its
// frosted-glass treatment, centered composition and falling snow. Derived from
// that file rather than sharing its layout: the greeter authenticates an
// arbitrary user through greetd instead of unlocking a known session, so it
// carries a username field and power controls and drops the now-playing card,
// which has no meaning before a session exists.
//
// Auth lives in GreetdSession.qml; this file is only the surface.
Scope {
    id: root

    property string currentText: ""
    property bool showFailure: false

    // The focus ring: 0 username, 1 password, 2-4 the power controls. Tab
    // walks it forwards, Shift+Tab backwards, both wrapping, and Up/Down do
    // the same - a greeter runs before any assistive setup exists, so every
    // control has to be reachable without a mouse. Enter still advances from
    // username to password, which is the path through this screen people
    // actually take.
    property int focusedField: 0
    readonly property int focusSlots: 5

    function focusSlot(index) {
        const slot = ((index % root.focusSlots) + root.focusSlots) % root.focusSlots
        root.focusedField = slot
        if (slot === 0) usernameField.forceActiveFocus()
        else if (slot === 1) passwordField.forceActiveFocus()
        // A plain Item does not keep active focus across a key handler, so
        // while the ring points at a power control, `content` holds focus and
        // activates it on the control's behalf.
        else content.forceActiveFocus()
    }

    // Shared by every key handler so the ring behaves the same wherever focus
    // happens to be. Returns true when it consumed the event.
    function ringKey(event) {
        // Shift+Tab arrives as Key_Backtab on some paths and as Key_Tab with
        // the Shift modifier on others - Qt's Wayland plugin sends the latter.
        if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
            root.focusSlot(root.focusedField - 1)
            return true
        }
        if (event.key === Qt.Key_Tab) {
            const back = (event.modifiers & Qt.ShiftModifier) !== 0
            root.focusSlot(root.focusedField + (back ? -1 : 1))
            return true
        }
        if (event.key === Qt.Key_Down) {
            root.focusSlot(root.focusedField + 1)
            return true
        }
        return false
    }

    onCurrentTextChanged: root.showFailure = false

    GreetdSession {
        id: session

        onAuthenticated: session.startSession()

        onFailedChanged: {
            if (!session.failed) return
            // Clear currentText BEFORE raising the flag. The field's own
            // handler also blanks itself, and that write would otherwise fire
            // onCurrentTextChanged -> showFailure = false and wipe the
            // rejection out of the UI before it was ever drawn. Clearing
            // first means the field's write is a no-op change that emits
            // nothing. LockLight.qml orders it the same way, for the same
            // reason.
            root.currentText = ""
            root.showFailure = true
        }
    }

    property var currentTime: new Date()
    Timer {
        running: true
        repeat: true
        interval: 1000
        triggeredOnStart: true
        onTriggered: root.currentTime = new Date()
    }

    // Empty until the fetch succeeds: at greeter time the wifi link may not
    // be associated yet, and a blank slot reads better than a stale
    // placeholder or an error string sitting on the login screen.
    property string tempText: ""
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
                    root.tempText = ""
                }
            }
        }
    }
    Timer {
        running: true
        repeat: true
        interval: 10 * 60 * 1000
        triggeredOnStart: true
        onTriggered: weatherProc.running = true
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
        // strength, e.g. bound to the surface's fade-in progress.
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

    // A greeter is not locking an existing session, so this is an ordinary
    // fullscreen layer-shell panel rather than a WlSessionLockSurface. It
    // takes exclusive keyboard focus because typing is the whole point.
    PanelWindow {
        id: surface

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "@lockBg@"

        function submitUsername() {
            if (usernameField.text.trim() === "") return
            root.focusSlot(1)
        }

        function submitPassword() {
            if (session.busy) return
            session.authenticate(usernameField.text.trim(), passwordField.text)
        }

        Item {
            id: content
            anchors.fill: parent
            focus: true
            opacity: 0

            Behavior on opacity {
                NumberAnimation { duration: 350; easing.type: Easing.InOutQuad }
            }

            Component.onCompleted: {
                content.opacity = 1
                usernameField.forceActiveFocus()
            }

            Keys.onPressed: event => {
                if (root.ringKey(event)) {
                    event.accepted = true
                    return
                }
                if (root.focusedField < 2) return

                if (event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                    powerControls.itemAt(root.focusedField - 2).fire()
                    event.accepted = true
                    return
                }
                // A way back to typing without cycling the whole ring.
                if (event.key === Qt.Key_Escape) {
                    root.focusSlot(1)
                    event.accepted = true
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
                running: true
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
                    font.family: "Nunito"
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
                    font.family: "Nunito"
                    font.weight: Font.Bold
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
                visible: root.tempText !== ""

                RowLayout {
                    id: tempRow
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        text: root.tempText
                        color: "#FFFFFFFF"
                        font.pixelSize: 15
                        font.family: "Nunito"
                        font.weight: Font.Bold
                    }
                }
            }

            // ── Identity pane, directly above the key pane. Same glass, same
            // centering: one column you move down through.
            GlassPanel {
                id: userPanel
                bgSource: bg.source
                bgWidth: surface.width
                bgHeight: surface.height
                radius: 26
                showBorder: false
                blurAmount: content.opacity

                anchors.bottom: passPanel.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 16
                width: 340
                height: 50
                opacity: root.focusedField === 0 ? 1.0 : 0.55

                Behavior on opacity { NumberAnimation { duration: 140 } }

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24

                    TextInput {
                        id: usernameField
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        text: "ogama"
                        color: "#FFFFFFFF"
                        font.pixelSize: 16
                        font.family: "Nunito"
                        font.bold: true

                        // Selection recolors the glyphs and draws nothing
                        // behind them. Mint rather than the palette's red:
                        // red already means rejection on this surface, and a
                        // selected username is not an error.
                        selectionColor: "transparent"
                        selectedTextColor: "@greenColor@"

                        cursorVisible: false
                        // Qt's TextInput forces cursorVisible back to true
                        // internally on every focus-in
                        // (ItemActiveFocusHasChanged), silently breaking the
                        // plain binding above - reassert it every time that
                        // happens instead. Same treatment as passwordField.
                        onCursorVisibleChanged: if (cursorVisible) cursorVisible = false

                        enabled: !session.busy
                        onAccepted: surface.submitUsername()
                        onActiveFocusChanged: if (activeFocus) root.focusedField = 0

                        // Qt's own tab chain would move focus out from under
                        // the ring and leave focusedField stale, so the ring
                        // owns Tab outright.
                        activeFocusOnTab: false

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                                usernameField.selectAll()
                                event.accepted = true
                                return
                            }
                            if (root.ringKey(event)) event.accepted = true
                        }

                        HoverHandler { cursorShape: Qt.ArrowCursor }
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
                opacity: root.focusedField === 1 ? 1.0 : 0.55

                Behavior on opacity { NumberAnimation { duration: 140 } }

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
                            font.family: "Nunito"
                            font.bold: true
                            echoMode: TextInput.Password
                            enabled: !session.busy

                            // Hides the I-beam mouse cursor over the field -
                            // HoverHandler tracks hover without consuming
                            // press events, unlike a MouseArea.
                            HoverHandler {
                                cursorShape: Qt.ArrowCursor
                            }

                            onTextChanged: root.currentText = text
                            onAccepted: surface.submitPassword()
                            onActiveFocusChanged: if (activeFocus) root.focusedField = 1

                            activeFocusOnTab: false

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                                    passwordField.selectAll()
                                    event.accepted = true
                                    return
                                }
                                if (root.ringKey(event)) event.accepted = true
                            }

                            // Clears the rejected password and hands focus
                            // back for a retry. Kept local to this field's
                            // own scope rather than wired from GreetdSession
                            // at the top of the file: reaching this id from
                            // outside the panel it is declared in throws
                            // "passwordField is not defined" at runtime.
                            Connections {
                                target: session
                                function onFailedChanged() {
                                    if (!session.failed) return
                                    passwordField.text = ""
                                    root.focusSlot(1)
                                }
                            }
                        }

                        // Dots fade+pop in one at a time as you type, instead
                        // of the raw echo-mode glyphs appearing instantly.
                        Row {
                            id: dotRow
                            anchors.centerIn: parent
                            spacing: 10

                            Repeater {
                                model: root.currentText.length

                                delegate: Rectangle {
                                    id: dot
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    // Every dot turns mint when the field is
                                    // fully selected, matching the username's
                                    // glyphs: the field renders none of its
                                    // own, so this recolor is the whole
                                    // selection signal.
                                    color: passwordField.selectedText.length > 0
                                        ? "@greenColor@"
                                        : "#FFFFFFFF"
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
                        visible: session.busy
                        text: "…"
                        color: "#CCFFFFFF"
                        font.pixelSize: 18
                        font.family: "Nunito"
                        font.bold: true
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

            Text {
                anchors.top: passPanel.bottom
                anchors.topMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.showFailure
                text: "Incorrect password"
                color: "#FFE0A0A0"
                font.pixelSize: 13
                font.family: "Nunito"
                font.bold: true

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#99000000"
                    shadowBlur: 0.5
                }
            }

            // ── Power controls, bottom-right, clear of the centered column
            // so they read as machine-level actions rather than part of the
            // login form.
            Row {
                spacing: 20
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 32

                Repeater {
                    id: powerControls

                    model: [
                        { label: "suspend", arg: "suspend" },
                        { label: "restart", arg: "reboot" },
                        { label: "shut down", arg: "poweroff" }
                    ]

                    delegate: Text {
                        id: control

                        required property int index
                        required property var modelData

                        // Hover and the keyboard ring are one state: a single
                        // highlight with two ways into it, rather than a mouse
                        // treatment and a separate focus ring.
                        readonly property bool energized: root.focusedField === 2 + control.index
                            || powerArea.containsMouse
                        property bool firing: false

                        text: modelData.label
                        color: control.firing || control.energized ? "@tempColor@" : "#CCFFFFFF"
                        font.pixelSize: 14
                        font.family: "Nunito"
                        font.bold: true

                        Behavior on color { ColorAnimation { duration: 130 } }

                        // The brief hold before the machine goes down is the
                        // only acknowledgement there is room for: the screen
                        // is about to disappear.
                        function fire() {
                            if (control.firing) return
                            control.firing = true
                            fireDelay.start()
                        }

                        Timer {
                            id: fireDelay
                            interval: 160
                            onTriggered: powerProc.running = true
                        }

                        Process {
                            id: powerProc
                            command: [ "@systemctlBin@", modelData.arg ]
                        }

                        MouseArea {
                            id: powerArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.focusSlot(2 + control.index)
                                control.fire()
                            }
                        }
                    }
                }
            }
        }
    }
}
