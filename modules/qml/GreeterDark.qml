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

    // 0 = username, 1 = password. Both fields are reachable with Up/Down, and
    // Enter advances from one to the other, so the whole screen is usable
    // without ever touching the mouse.
    property int focusedField: 0

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
            if (session.failed) root.showFailure = true
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

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                    root.focusedField = root.focusedField === 0 ? 1 : 0
                    if (root.focusedField === 0) usernameField.forceActiveFocus()
                    else passwordField.forceActiveFocus()
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

                anchors.left: parent.left
                anchors.bottom: passPanel.top
                anchors.leftMargin: Math.round(parent.width * 0.09) + 14
                anchors.bottomMargin: 18
                width: 300
                height: 50
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
                            font.family: "Inter"
                            font.pixelSize: 16

                            // Selection as a hard-edged stencil block, not a
                            // rounded highlight: the glyphs knock out of the
                            // accent, matching the angular panels this design
                            // is built from.
                            selectionColor: root.accentMagenta
                            selectedTextColor: "#1C1E26"

                            enabled: !session.busy
                            onAccepted: surface.submitUsername()
                            onActiveFocusChanged: if (activeFocus) root.focusedField = 0

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                                    usernameField.selectAll()
                                    event.accepted = true
                                }
                            }

                            HoverHandler { cursorShape: Qt.ArrowCursor }
                        }
                    }
                }

                // 2px tick marking which field has focus.
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 10
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    width: 2
                    color: root.accentCyan
                    visible: root.focusedField === 0
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

                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: Math.round(parent.width * 0.09)
                anchors.bottomMargin: Math.round(parent.height * 0.09)
                width: 340
                height: 58
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

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                                    passwordField.selectAll()
                                    event.accepted = true
                                }
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
                            spacing: 9

                            Repeater {
                                model: root.currentText.length

                                delegate: Rectangle {
                                    id: dot
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    // All dots go magenta when the field is
                                    // fully selected: the field renders no
                                    // glyphs, so a normal selection rectangle
                                    // would have nothing to highlight.
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

                        // Selection rule under the dots - the second half of
                        // the "everything is selected" signal.
                        Rectangle {
                            anchors.left: dotRow.left
                            anchors.right: dotRow.right
                            anchors.top: dotRow.bottom
                            anchors.topMargin: 4
                            height: 2
                            color: root.accentCyan
                            visible: passwordField.selectedText.length > 0
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
            Row {
                spacing: 20
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: Math.round(parent.width * 0.04)
                anchors.bottomMargin: Math.round(parent.height * 0.09)

                Repeater {
                    model: [
                        { label: "suspend", arg: "suspend" },
                        { label: "restart", arg: "reboot" },
                        { label: "shut down", arg: "poweroff" }
                    ]

                    delegate: Text {
                        required property var modelData

                        text: modelData.label
                        color: powerArea.containsMouse
                            ? root.accentAmber
                            : root.withAlpha(root.smokeLavender, 0.65)
                        font.family: "Inter"
                        font.pixelSize: 14

                        Process {
                            id: powerProc
                            command: [ "@systemctlBin@", modelData.arg ]
                        }

                        MouseArea {
                            id: powerArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: powerProc.running = true
                        }
                    }
                }
            }
        }
    }
}
