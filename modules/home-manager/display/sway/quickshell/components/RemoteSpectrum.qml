import QtQuick

// A stand-in spectrum for music that is playing somewhere else.
//
// kdeconnect hands over the phone's metadata and its transport controls but
// not one sample of its audio - the sound comes out of the phone. cava reads
// THIS machine's output, which during a phone track is silence, so the wave
// would lie flat through an entire song.
//
// So the bands are generated. Plain sines, not noise: random bands jitter at
// this size and the smoothing downstream cannot hide it. The two speeds beat
// against each other, and a slow envelope rides over both, so the pattern
// does not visibly loop.
//
// It is not the phone's audio and never pretends to be - every surface that
// draws this also draws the remote marker next to the artist.
Item {
    id: root

    property bool running: false
    // cava's own count, so a consumer that averages bands into its bars
    // (MusicWidget) sees the same shape of input either way.
    property int bands: 20

    // 0..100, the units cava emits.
    property var levels: []

    property real phase: 0

    // 30fps, not 60: both consumers interpolate between frames on their own
    // tick, so the extra half would be work nobody can see.
    Timer {
        interval: 33
        repeat: true
        running: root.running
        onTriggered: {
            root.phase += 0.11
            const out = []
            const last = Math.max(1, root.bands - 1)
            const env = 0.6 + 0.4 * Math.sin(root.phase * 0.23)
            for (let i = 0; i < root.bands; i++) {
                // Falls away toward the high bands, the way a real spectrum
                // does - a flat-topped block would read as a test pattern.
                const tilt = 1 - 0.45 * (i / last)
                const slow = 0.5 + 0.5 * Math.sin(root.phase * 0.7 + i * 0.35)
                const fast = 0.5 + 0.5 * Math.sin(root.phase * 1.9 - i * 0.8)
                const mix = 0.6 * slow + 0.4 * fast
                out.push(100 * tilt * env * (0.25 + 0.75 * mix))
            }
            root.levels = out
        }
    }

    // Dropped rather than frozen, so the consumers' own settle animation
    // takes the bars back down to the resting line.
    onRunningChanged: if (!root.running) root.levels = []
}
