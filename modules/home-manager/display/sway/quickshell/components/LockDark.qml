import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Services.Mpris

// Minimal dark-mode lockscreen, selected instead of LockLight.qml when
// stylix.polarity is "dark" (see ../default.nix). Deliberately plain - a
// starting point to be customized, not the full glass/snow treatment of
// the light variant.
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
                root.locked = false
                // The GPU context can come back wedged after a suspend/resume
                // cycle (known amdgpu resume bug on this hardware), leaving
                // the widgets blank. Only safe to restart once we're
                // provably unlocked - never while this process might still
                // hold the session lock.
                postUnlockRestart.restart()
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

    Process {
        id: restartWidgets
        command: [ "@systemctlBin@", "--user", "restart", "quickshell-widgets" ]
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.locked = true }
        function unlock(): void { root.locked = false }
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

    WlSessionLock {
        id: sessionLock
        locked: root.locked

        WlSessionLockSurface {
            color: "@lockBg@"

            Rectangle {
                anchors.centerIn: parent
                width: 460
                height: 380
                radius: 40
                color: "@cardBg@"
                border.color: "@cardBorder@"
                border.width: 2

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16
                    width: parent.width - 80

                    Text {
                        id: clock
                        Layout.alignment: Qt.AlignHCenter
                        color: "@clockColor@"
                        font.pixelSize: 56
                        font.weight: Font.DemiBold

                        property var date: new Date()
                        text: Qt.formatDateTime(date, "HH:mm")

                        Timer {
                            running: true
                            repeat: true
                            interval: 1000
                            onTriggered: clock.date = new Date()
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDateTime(clock.date, "dddd d MMMM")
                        color: "@dateColor@"
                        font.pixelSize: 20
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.tempText
                        color: "@tempColor@"
                        font.pixelSize: 16
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 8
                        Layout.preferredWidth: 200
                        height: 2
                        color: "@dividerColor@"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        height: 48
                        radius: 24
                        color: "@cardBorder@"
                        border.color: root.showFailure ? "@tempColor@" : "transparent"
                        border.width: 2

                        TextInput {
                            id: passwordField
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            verticalAlignment: TextInput.AlignVCenter
                            color: "@clockColor@"
                            font.pixelSize: 18
                            echoMode: TextInput.Password
                            enabled: !root.unlockInProgress
                            focus: true

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
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.showFailure
                        text: "Incorrect password"
                        color: "@tempColor@"
                        font.pixelSize: 14
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        Layout.maximumWidth: parent.width
                        visible: root.activePlayer !== null
                        elide: Text.ElideRight
                        text: root.activePlayer ? ("♪ " + root.activePlayer.trackTitle + " — " + root.activePlayer.trackArtist) : ""
                        color: "@dateColor@"
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
