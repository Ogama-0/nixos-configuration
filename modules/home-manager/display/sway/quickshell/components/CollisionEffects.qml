import QtQuick
import QtQuick.Effects
import QtQuick.Particles

// The meeting-point payoff once both beams finish traveling: a bright core
// flare, a subtle anamorphic streak blending the two accent colors, and a
// burst of particles - all deliberately delayed until `collisionDelay`
// after `active` flips (not blended in during the approach), so they read
// as a reaction to the collision rather than something that ramps up
// alongside it. `collided` tracks that delayed state internally; nothing
// outside this component needs it.
Item {
    id: root

    required property bool active
    required property real meetX
    required property real panelWidth
    required property real beamY
    property int collisionDelay: 150

    property bool collided: false

    Timer {
        id: collisionTimer
        interval: root.collisionDelay
        onTriggered: {
            root.collided = true
            clashEmitter.burst(50)
        }
    }

    onActiveChanged: {
        if (active) {
            collisionTimer.restart()
        } else {
            collisionTimer.stop()
            root.collided = false
        }
    }

    Rectangle {
        id: flare
        width: 28
        height: 28
        radius: 14
        y: root.beamY - height / 2
        x: Math.max(0, Math.min(root.panelWidth - width, root.meetX - width / 2))
        color: "#FFFFFF"
        opacity: root.collided ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 80 }
        }
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 24
        }
    }

    Rectangle {
        id: flareStreakGlow
        width: 140
        height: 20
        y: root.beamY - height / 2
        x: flare.x + flare.width / 2 - width / 2
        opacity: root.collided ? 0.5 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 80 }
        }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.35; color: "@greenColor@" }
            GradientStop { position: 0.5; color: "#FFFFFF" }
            GradientStop { position: 0.65; color: "@redColor@" }
            GradientStop { position: 1.0; color: "transparent" }
        }
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 20
        }
    }

    Rectangle {
        id: flareStreak
        width: 110
        height: 5
        y: root.beamY - height / 2
        x: flare.x + flare.width / 2 - width / 2
        opacity: root.collided ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 80 }
        }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.35; color: "@greenColor@" }
            GradientStop { position: 0.5; color: "#FFFFFF" }
            GradientStop { position: 0.65; color: "@redColor@" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    ParticleSystem {
        id: clashSystem
        running: true
    }

    Emitter {
        id: clashEmitter
        system: clashSystem
        enabled: root.collided
        x: flare.x + flare.width / 2
        y: flare.y + flare.height / 2
        emitRate: 18
        lifeSpan: 400
        lifeSpanVariation: 150
        size: 6
        sizeVariation: 3
        endSize: 0
        velocity: AngleDirection {
            angle: 0
            angleVariation: 360
            magnitude: 140
            magnitudeVariation: 80
        }
    }

    ImageParticle {
        system: clashSystem
        source: "qrc:///particleresources/glowdot.png"
        color: "#FFFFFF"
        colorVariation: 0.15
        alpha: 0.9
        alphaVariation: 0.1
        entryEffect: ImageParticle.Fade
    }
}
