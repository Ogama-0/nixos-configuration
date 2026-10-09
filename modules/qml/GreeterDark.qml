import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

// Dark-mode greeter - the login-screen sibling of LockDark.qml, built around
// the same Arcane/Jinx artwork and the same flat angular stencil panels with
// neon edge-glow. Derived from that file rather than sharing its layout: the
// greeter authenticates an arbitrary user through greetd instead of unlocking
// a known session, so it carries a username field and power controls and
// drops the now-playing ticket, which has no meaning before a session exists.
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
        else content.forceActiveFocus()
    }

    // Shared by every key handler on the surface so the ring behaves the same
    // wherever focus happens to be. Returns true when it consumed the event.
    function ringKey(event) {
        // Shift+Tab arrives as Key_Backtab on some paths and as Key_Tab with
        // the Shift modifier on others - Qt's Wayland plugin sends the latter
        // here - so both spellings have to mean backwards, or Shift+Tab walks
        // the ring the wrong way.
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
            // nothing. LockDark.qml orders it the same way, for the same
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
    // keeps the greeter in the same visual language as the bar's
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

    // One current-sweep along the lower inside edge of a panel, fired when
    // that panel wakes up. Shared by the two fields and the three power
    // controls so everything on the surface energizes the same way, and so
    // the timing only has to be tuned in one place. Sits inside the stroke
    // rather than on it: the 3px border would hide a bar drawn on the edge.
    component EdgeSurge: Item {
        id: surgeRoot

        property color accent: root.accentCyan

        // The panel's chamfer. Clipping is rectangular, so the clip is pulled
        // in off the right edge by this much: otherwise the tail of the bar is
        // drawn in the triangle outside the cut corner, past the stroke, and
        // reads as a stray mark flicking off the end. Holding the bar back
        // instead would be the obvious fix and the wrong one - it has to keep
        // leaving at full speed, or the sweep feels like it is dragging.
        property real inset: 0

        anchors.fill: parent
        anchors.rightMargin: surgeRoot.inset
        clip: true

        function run() {
            // Before the panel has been sized there is nothing to sweep
            // across, and running anyway animates x from 0 to 0 - which parks
            // the bar at the left edge of the panel for good, because the
            // animation writes x imperatively and nothing moves it again.
            if (surgeRoot.width <= 0) return
            surgeAnim.restart()
        }

        Rectangle {
            id: surgeBar
            // The bar exists only while it is travelling. Belt and braces
            // against it ever being left visible at rest.
            visible: surgeAnim.running
            width: Math.round(surgeRoot.width * 0.45)
            height: 2
            y: surgeRoot.height - 7
            x: -width
            // Bright, but still the panel's own color. Lightened much past
            // this it washes out to white and stops reading as that accent.
            color: Qt.lighter(surgeRoot.accent, 1.2)
            opacity: 0.9
            // The placards sit at a slight angle, so an unsmoothed 2px bar
            // stair-steps along its length.
            antialiasing: true
        }

        NumberAnimation {
            id: surgeAnim
            target: surgeBar
            property: "x"
            from: -surgeBar.width
            to: surgeRoot.width
            duration: 420
            easing.type: Easing.OutCubic
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
            root.focusedField = 1
            passwordField.forceActiveFocus()
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
                flickerAnim.start()
                usernameField.forceActiveFocus()
            }

            // Every key that is not typing goes through here. The power
            // controls hold no focus of their own - a plain Item does not keep
            // active focus across a key handler - so while the ring points at
            // one, `content` is the focused item and activates it on its
            // behalf.
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
            // tag thrown up in the corner of the shot, not a dashboard.
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
                    visible: root.tempText !== ""
                    color: root.smokeLavender
                    font.family: "Inter"
                    font.pixelSize: 15
                }
            }

            // ── Identity tag, sitting just above the key tag. Two thrown-on
            // stickers rather than one wide form: the username is a label on
            // the frame, the password is the thing you act on.
            TagPanel {
                id: userPanel
                accentColor: root.accentCyan
                fill: "#E60C2426"
                cut: 12

                // Taking focus is the field waking up, so it gets the same
                // sweep the power controls get.
                readonly property bool lit: root.focusedField === 0
                onLitChanged: if (userPanel.lit) userSurge.run()

                EdgeSurge {
                    id: userSurge
                    accent: userPanel.accentColor
                    inset: userPanel.cut
                }

                // Placed from a rectangle picked against the real 1920x1080
                // render and stored as a fraction of the surface, the same way
                // the power controls are. Positioned by centre so a size
                // change grows the panel both ways instead of walking it
                // across the frame.
                x: Math.round(parent.width * 0.3521 - width / 2)
                y: Math.round(parent.height * 0.7995 - height / 2)
                width: 268
                height: 49
                rotation: -0.6
                opacity: root.focusedField === 0 ? 1.0 : 0.35

                Behavior on opacity { NumberAnimation { duration: 140 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 20
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TextInput {
                            id: usernameField
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "ogama"
                            color: root.paperWhite
                            font.family: "Orbitron"
                            font.pixelSize: 15
                            font.bold: true
                            font.letterSpacing: 0.5

                            // Selection recolors the glyphs and nothing else
                            // - no highlight block behind them, matching the
                            // password dots, which signal the same way.
                            selectionColor: "transparent"
                            selectedTextColor: root.accentMagenta

                            cursorVisible: false
                            // Qt's TextInput forces cursorVisible back to true
                            // internally on every focus-in
                            // (ItemActiveFocusHasChanged), silently breaking
                            // the plain binding above - reassert it every time
                            // that happens instead. Same treatment as
                            // passwordField below.
                            onCursorVisibleChanged: if (cursorVisible) cursorVisible = false

                            enabled: !session.busy
                            onAccepted: surface.submitUsername()
                            onActiveFocusChanged: if (activeFocus) root.focusedField = 0

                            // Qt's own tab chain would move focus out from
                            // under the ring and leave focusedField stale, so
                            // the ring owns Tab outright.
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
            }

            // ── Key tag, bottom-left: a stenciled tag stuck low in the
            // frame, pulled in off the very edge and clear of the glowing
            // enforcer-head/blade above it and the explosion on the right.
            TagPanel {
                id: passPanel
                accentColor: root.showFailure ? root.accentAmber : root.accentMagenta
                fill: root.showFailure ? "#E6241206" : "#E6240420"
                cut: 16

                readonly property bool lit: root.focusedField === 1
                onLitChanged: if (passPanel.lit) passSurge.run()

                EdgeSurge {
                    id: passSurge
                    accent: passPanel.accentColor
                    inset: passPanel.cut
                }

                // The rejection shake animates this, not x: writing x
                // directly would destroy the binding below on the first
                // failure, and while this panel was anchored the anchor simply
                // overrode x and the shake never moved anything.
                property real shakeOffset: 0

                x: Math.round(parent.width * 0.2776 - width / 2) + passPanel.shakeOffset
                y: Math.round(parent.height * 0.8597 - height / 2)
                // Matched to the username panel rather than restated, so the
                // two stay the same size if either is ever resized.
                width: userPanel.width
                height: userPanel.height
                rotation: -1.3
                opacity: root.focusedField === 1 ? 1.0 : 0.35

                Behavior on opacity { NumberAnimation { duration: 140 } }

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
                            visible: root.currentText.length === 0 && !session.busy
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
                            enabled: !session.busy

                            // Hides the I-beam mouse cursor over the
                            // field - HoverHandler tracks hover without
                            // consuming press events, unlike a MouseArea.
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
                            // outside the TagPanel it is declared in throws
                            // "passwordField is not defined" at runtime.
                            Connections {
                                target: session
                                function onFailedChanged() {
                                    if (!session.failed) return
                                    passwordField.text = ""
                                    root.focusedField = 1
                                    passwordField.forceActiveFocus()
                                }
                            }
                        }

                        // Drips of paint falling in as each character is
                        // typed, instead of the raw password glyphs.
                        Row {
                            id: dotRow
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7

                            Repeater {
                                model: root.currentText.length

                                delegate: Rectangle {
                                    id: dot
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    // All dots go magenta when the field is
                                    // fully selected, instead of alternating
                                    // magenta/cyan. The field renders no
                                    // glyphs, so this recolor is the whole
                                    // selection signal.
                                    color: passwordField.selectedText.length > 0
                                        ? root.accentMagenta
                                        : (index % 2 === 0 ? root.accentMagenta : root.accentCyan)
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
                        visible: session.busy
                        text: "…"
                        color: root.smokeLavender
                        font.pixelSize: 18
                    }
                }
            }

            SequentialAnimation {
                id: shakeAnim
                loops: 1
                NumberAnimation { target: passPanel; property: "shakeOffset"; to: -10; duration: 45 }
                NumberAnimation { target: passPanel; property: "shakeOffset"; to: 10; duration: 45 }
                NumberAnimation { target: passPanel; property: "shakeOffset"; to: -6; duration: 45 }
                NumberAnimation { target: passPanel; property: "shakeOffset"; to: 0; duration: 45 }
            }

            Connections {
                target: root
                function onShowFailureChanged() {
                    if (root.showFailure) shakeAnim.restart()
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

            // ── Power controls, opposite corner from the tags so they read
            // as machine-level actions rather than part of the login form.
            // Each control carries the color of what it costs you: cyan for
            // the reversible one, magenta for the disruptive one, and amber -
            // the same amber as ACCESS DENIED - for the one you do not undo.
            // At rest the row is three quiet labels and nothing else, so it
            // never competes with the artwork; the chip only exists while a
            // control is live under the pointer or the focus ring.
            // Placed along the dark blade sweeping down the right of the
            // artwork rather than set in a level row: the three controls
            // cascade with it, so they sit in the frame instead of on top of
            // it. The centres were picked against the real 1920x1080 render
            // and stored as fractions of the surface. The drop between them is
            // kept equal while the horizontal step follows the blade, which
            // falls away faster lower down. The chips stay level; at the
            // blade's ~48 degrees, rotated labels stop being readable.
            Item {
                anchors.fill: parent

                Repeater {
                    id: powerControls

                    model: [
                        { label: "suspend", arg: "suspend", accent: root.accentCyan,
                          cx: 0.8928, cy: 0.8130 },
                        { label: "restart", arg: "reboot", accent: root.accentMagenta,
                          cx: 0.9104, cy: 0.8454 },
                        { label: "shut down", arg: "poweroff", accent: root.accentAmber,
                          cx: 0.9259, cy: 0.8778 }
                    ]

                    delegate: Item {
                        id: chip

                        required property int index
                        required property var modelData

                        // Hover and the keyboard ring are deliberately one
                        // state: a single highlight with two ways into it,
                        // rather than a mouse treatment and a separate focus
                        // ring.
                        readonly property bool energized: root.focusedField === 2 + chip.index
                            || powerArea.containsMouse
                        property bool firing: false

                        implicitWidth: powerLabel.implicitWidth + 30
                        implicitHeight: 30

                        // Positioned by centre so a longer label grows both
                        // ways and stays on the blade instead of drifting off
                        // the end of it.
                        x: Math.round(parent.width * modelData.cx - width / 2)
                        y: Math.round(parent.height * modelData.cy - height / 2)

                        scale: powerArea.pressed || chip.firing ? 0.95 : 1.0
                        Behavior on scale {
                            NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                        }

                        // The brief hold before the machine goes down is the
                        // only acknowledgement there is room for: the screen
                        // is about to disappear, so the confirmation has to
                        // land before the action, not after it.
                        function fire() {
                            if (chip.firing) return
                            chip.firing = true
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

                        TagPanel {
                            anchors.fill: parent
                            cut: 8
                            accentColor: modelData.accent
                            fill: root.withAlpha(modelData.accent, 0.12)
                            opacity: chip.energized ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation { duration: 130; easing.type: Easing.OutQuad }
                            }

                            EdgeSurge {
                                id: chipSurge
                                accent: modelData.accent
                                inset: 8
                            }
                        }

                        onEnergizedChanged: if (chip.energized) chipSurge.run()

                        Text {
                            id: powerLabel
                            anchors.centerIn: parent

                            text: modelData.label
                            color: chip.firing
                                ? root.paperWhite
                                : chip.energized
                                    ? modelData.accent
                                    : root.withAlpha(root.smokeLavender, 0.65)
                            font.family: "Orbitron"
                            font.pixelSize: 12
                            font.bold: true
                            // Opening the tracking as it lights up gives the
                            // label somewhere to go that is not just brighter.
                            font.letterSpacing: chip.energized ? 1.8 : 1.2

                            Behavior on color { ColorAnimation { duration: 130 } }
                            Behavior on font.letterSpacing {
                                NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
                            }
                        }

                        MouseArea {
                            id: powerArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.focusSlot(2 + chip.index)
                                chip.fire()
                            }
                        }
                    }
                }
            }
        }
    }
}
