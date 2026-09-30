import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// The centered time/date bar module: a GlassPill (see GlassPill.qml for the
// reusable "liquid glass, revealed by the beams" template) holding a
// dual-tone glow time readout, the date, and a tiny animated sine squiggle
// echoing the beams either side of it.
//
// This is the reference example for writing a new module: instantiate
// GlassPill as your root, feed it coverLeft/coverRight/panelWidth from the
// panel, size it via contentWidth/contentHeight, and put your own content
// inside.
GlassPill {
    id: root

    required property bool active

    contentWidth: 220
    contentHeight: 64

    ColorUtils {
        id: colorUtils
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 3

        // Dual-tone neon glow behind the crisp time text: a blurred green
        // copy and a blurred red copy stacked underneath, both bound to
        // clockText's own text/font so they never need updating separately.
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: clockText.implicitWidth
            implicitHeight: clockText.implicitHeight

            Text {
                anchors.centerIn: parent
                text: clockText.text
                font: clockText.font
                color: "@greenColor@"
                opacity: 0.55
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 8 }
            }
            Text {
                anchors.centerIn: parent
                text: clockText.text
                font: clockText.font
                color: "@redColor@"
                opacity: 0.55
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 8 }
            }
            Text {
                id: clockText
                anchors.centerIn: parent
                color: "@clockColor@"
                font.pixelSize: 20
                font.weight: Font.DemiBold

                // Dark drop shadow for legibility against the wave strands
                // showing through the glass behind it, independent of the
                // green/red glow above.
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#CC000000"
                    shadowBlur: 0.6
                    shadowVerticalOffset: 1
                }
            }
        }

        Text {
            id: dateText
            Layout.alignment: Qt.AlignHCenter
            color: "@dateColor@"
            font.pixelSize: 12

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#CC000000"
                shadowBlur: 0.6
                shadowVerticalOffset: 1
            }
        }

        // Signature accent: a tiny animated sine squiggle, same technique
        // as the beams, shrunk down - green half then red half, echoing
        // the beams either side of this pill.
        Canvas {
            id: clockWave
            Layout.alignment: Qt.AlignHCenter
            width: 64
            height: 8
            renderStrategy: Canvas.Immediate

            property real wavePhase: 0

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const midY = height / 2
                const half = width / 2

                ctx.lineWidth = 1.6
                ctx.lineCap = "round"
                ctx.globalAlpha = 0.8

                ctx.strokeStyle = colorUtils.lightenColor("@greenColor@", 0.3)
                ctx.beginPath()
                for (let x = 0; x <= half; x += 2) {
                    const y = midY + 2.6 * Math.sin(x / 6 + clockWave.wavePhase)
                    if (x === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.stroke()

                ctx.strokeStyle = colorUtils.lightenColor("@redColor@", 0.3)
                ctx.beginPath()
                for (let x = half; x <= width; x += 2) {
                    const y = midY + 2.6 * Math.sin(x / 6 + clockWave.wavePhase)
                    if (x === half) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.stroke()
                ctx.globalAlpha = 1
            }

            Timer {
                interval: 33
                repeat: true
                running: root.active
                onTriggered: clockWave.wavePhase += 0.12
            }

            onWavePhaseChanged: requestPaint()
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            clockText.text = Qt.formatDateTime(now, "HH:mm:ss")
            dateText.text = Qt.formatDateTime(now, "dddd d MMMM")
        }
    }
}
