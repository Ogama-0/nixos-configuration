import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

PanelWindow {
    id: root

    property var cavaValues: []

    property var activePlayer: {
        const list = Mpris.players.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].isPlaying) return list[i]
        }
        return list.length > 0 ? list[0] : null
    }

    // quickshell's MprisPlayer.position is a locally-interpolated value that
    // only resyncs on a playback-status transition or a Seeked signal, neither
    // of which most players emit on Next()/Previous() -- so it goes stale across
    // a track skip. Poll the real value via playerctl instead.
    property real livePosition: 0

    readonly property string trackKey: root.activePlayer
        ? (root.activePlayer.trackTitle + "|" + root.activePlayer.trackArtist + "|" + root.activePlayer.trackAlbum)
        : ""

    onTrackKeyChanged: root.livePosition = 0

    function artUrl(player) {
        if (!player) return ""
        if (player.trackArtUrl) return player.trackArtUrl
        const url = player.metadata ? (player.metadata["xesam:url"] || "") : ""
        if (url.startsWith("https://www.youtube.com/watch")) {
            const m = url.match(/[?&]v=([\w-]{11})/)
            return m ? `https://img.youtube.com/vi/${m[1]}/hqdefault.jpg` : ""
        }
        return ""
    }

    function formatTime(sec) {
        if (!sec || sec < 0 || !isFinite(sec)) return "0:00"
        const total = Math.floor(sec)
        const m = Math.floor(total / 60)
        const s = total % 60
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    anchors {
        top: true
        right: true
    }
    margins {
        top: 280
        right: 24
    }

    implicitWidth: 440
    implicitHeight: 460
    color: "transparent"
    visible: root.activePlayer !== null && root.activePlayer.isPlaying

    WlrLayershell.namespace: "music-widget"
    WlrLayershell.layer: WlrLayer.Background

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    Process {
        id: cavaProc
        running: root.activePlayer !== null && root.activePlayer.isPlaying
        command: ["cava", "-p", Quickshell.shellDir + "/cava.conf"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const parts = data.split(";").filter(s => s.length > 0).map(Number)
                if (parts.length > 0) root.cavaValues = parts
            }
        }
    }

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
        interval: 500
        running: root.activePlayer !== null && root.activePlayer.isPlaying
        repeat: true
        triggeredOnStart: true
        onTriggered: positionProc.running = true
    }

    Rectangle {
        anchors.fill: parent
        radius: 40
        color: "@cardBg@"
        border.color: "@cardBorder@"
        border.width: 2

        ColumnLayout {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 28
                rightMargin: 28
            }
            spacing: 10

            Item {
                id: artArea
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                implicitWidth: 200
                implicitHeight: 200

                Repeater {
                    model: 20

                    delegate: Item {
                        required property int index

                        anchors.centerIn: parent
                        width: 1
                        height: 1
                        rotation: index * (360 / 20)

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: -68 - height
                            width: 3
                            radius: 1.5
                            height: 4 + ((index < root.cavaValues.length ? root.cavaValues[index] : 0) / 100) * 22
                            color: "@tempColor@"
                        }
                    }
                }

                Rectangle {
                    id: coverMask
                    anchors.centerIn: parent
                    width: 130
                    height: 130
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }

                Image {
                    id: coverImg
                    anchors.centerIn: parent
                    width: 130
                    height: 130
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: root.activePlayer ? root.artUrl(root.activePlayer) : ""

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: coverMask
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: coverImg.status !== Image.Ready
                    text: "♪"
                    font.pixelSize: 44
                    color: "@dateColor@"
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.activePlayer ? root.activePlayer.trackTitle : "No media playing"
                color: "@clockColor@"
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: root.activePlayer !== null
                text: root.activePlayer ? root.activePlayer.trackArtist : ""
                color: "@dateColor@"
                font.pixelSize: 16
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                Text {
                    text: root.formatTime(root.livePosition)
                    color: "@dateColor@"
                    font.pixelSize: 12
                }

                Item {
                    id: progressBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 8

                    readonly property real progress: (root.activePlayer && root.activePlayer.length > 0)
                        ? Math.max(0, Math.min(1, root.livePosition / root.activePlayer.length))
                        : 0

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: "@dividerColor@"
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: height / 2
                        width: parent.width * progressBar.progress
                        color: "@tempColor@"
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.activePlayer && root.activePlayer.canSeek
                        onClicked: mouse => {
                            if (root.activePlayer && root.activePlayer.length > 0) {
                                const target = Math.max(0, Math.min(1, mouse.x / width)) * root.activePlayer.length
                                root.activePlayer.position = target
                                root.livePosition = target
                            }
                        }
                    }
                }

                Text {
                    text: root.formatTime(root.activePlayer ? root.activePlayer.length : 0)
                    color: "@dateColor@"
                    font.pixelSize: 12
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                spacing: 32

                Text {
                    text: "⏮"
                    font.pixelSize: 26
                    color: "@clockColor@"
                    opacity: (root.activePlayer && root.activePlayer.canGoPrevious) ? 1.0 : 0.35

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.activePlayer && root.activePlayer.canGoPrevious
                        onClicked: root.activePlayer.previous()
                    }
                }

                Text {
                    text: (root.activePlayer && root.activePlayer.isPlaying) ? "⏸" : "▶"
                    font.pixelSize: 26
                    color: "@clockColor@"
                    opacity: (root.activePlayer && root.activePlayer.canTogglePlaying) ? 1.0 : 0.35

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.activePlayer && root.activePlayer.canTogglePlaying
                        onClicked: root.activePlayer.togglePlaying()
                    }
                }

                Text {
                    text: "⏭"
                    font.pixelSize: 26
                    color: "@clockColor@"
                    opacity: (root.activePlayer && root.activePlayer.canGoNext) ? 1.0 : 0.35

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.activePlayer && root.activePlayer.canGoNext
                        onClicked: root.activePlayer.next()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 12

                Text {
                    text: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted) ? "🔇" : "🔊"
                    font.pixelSize: 18
                    color: "@tempColor@"

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
                                Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 10

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: "@dividerColor@"
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: height / 2
                        width: parent.width * Math.max(0, Math.min(1,
                            (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
                                ? Pipewire.defaultAudioSink.audio.volume : 0))
                        color: "@tempColor@"
                    }

                    MouseArea {
                        anchors.fill: parent

                        function setVolumeFromX(x) {
                            if (!Pipewire.defaultAudioSink || !Pipewire.defaultAudioSink.audio) return
                            Pipewire.defaultAudioSink.audio.volume = Math.max(0, Math.min(1, x / width))
                        }

                        onPressed: mouse => setVolumeFromX(mouse.x)
                        onPositionChanged: mouse => {
                            if (pressed) setVolumeFromX(mouse.x)
                        }
                        onWheel: wheel => {
                            if (!Pipewire.defaultAudioSink || !Pipewire.defaultAudioSink.audio) return
                            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                            Pipewire.defaultAudioSink.audio.volume =
                                Math.max(0, Math.min(1, Pipewire.defaultAudioSink.audio.volume + step))
                        }
                    }
                }
            }
        }
    }
}
