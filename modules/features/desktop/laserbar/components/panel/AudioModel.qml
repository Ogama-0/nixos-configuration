import QtQuick
import Quickshell.Services.Pipewire

// Where sound goes, and how loud.
//
// PipeWire over Quickshell's own binding rather than shelling out to wpctl:
// this is signal-driven, so there is no poll loop and no subprocess per tick.
Item {
    id: root

    property bool active: false

    // Real output devices only. isStream excludes applications, which are
    // also sinks as far as PipeWire is concerned - a list that offered
    // "Firefox" as somewhere to send your audio would be nonsense.
    readonly property var sinkNodes: {
        const out = [];
        const all = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (const n of all)
            if (n && n.isSink && !n.isStream) out.push(n);
        return out;
    }

    readonly property var sinks: sinkNodes.map(n => ({
        id: n.id,
        name: n.description || n.nickname || n.name,
        isDefault: Pipewire.defaultAudioSink
            ? n.id === Pipewire.defaultAudioSink.id : false
    }))

    readonly property var defaultSink: Pipewire.defaultAudioSink

    readonly property int volumePct:
        defaultSink && defaultSink.audio
            ? Math.round(defaultSink.audio.volume * 100) : 0

    readonly property bool muted:
        defaultSink && defaultSink.audio ? defaultSink.audio.muted : false

    readonly property string defaultName: {
        const d = defaultSink;
        if (!d) return "No output";
        return d.description || d.nickname || d.name;
    }

    function setSink(id) {
        for (const n of sinkNodes)
            if (n.id === id) { Pipewire.preferredDefaultAudioSink = n; return; }
    }

    function setVolume(pct) {
        const d = defaultSink;
        if (d && d.audio) d.audio.volume = Math.max(0, Math.min(100, pct)) / 100;
    }

    function toggleMute() {
        const d = defaultSink;
        if (d && d.audio) d.audio.muted = !d.audio.muted;
    }

    // Volume and mute live on the node's audio interface, which is only
    // populated for nodes something is actually tracking.
    PwObjectTracker {
        objects: root.sinkNodes
    }
}
