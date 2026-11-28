import QtQuick

// One clock for every relative timestamp on the desktop.
//
// "5m ago" has to be recomputed as time passes, and the obvious way to do
// that - a Timer inside each row - puts one repeating timer per notification
// on screen. Fifty entries in the centre would be fifty timers all waking to
// write the same three characters. So there is one here, it is passed down,
// and the rows bind to `now`.
//
// Gated, because it repeats: see rule 1 in docs/adding-a-bar-widget.md. The
// toasts turn it on while one is up and the panel turns it on while it is
// open; with neither, nothing is reading a timestamp and this must not tick.
//
// 15s is the coarsest interval that never shows a stale reading. The only
// transition anybody notices is "now" becoming "1m ago", and at 15s that is
// late by at most a quarter minute on a string whose own resolution is a
// whole one.
Item {
    id: root

    property bool active: false
    property real now: Date.now()

    // Deliberately not Qt.formatDateTime: these are durations, not dates,
    // and the phrasing has to stay short enough for a toast's header.
    //
    // `ts === 0` is a notification restored from a state file written before
    // timestamps existed. It renders as "earlier" rather than as "now",
    // which would be a confident lie about something days old.
    function relative(ts) {
        if (!ts) return "earlier";
        const s = Math.floor((now - ts) / 1000);
        if (s < 45) return "now";
        const m = Math.round(s / 60);
        if (m < 60) return m + "m ago";
        const h = Math.round(m / 60);
        if (h < 24) return h + "h ago";
        return Math.round(h / 24) + "d ago";
    }

    Timer {
        interval: 15000
        running: root.active
        repeat: true
        // So a toast arriving after a quiet spell reads a fresh `now` rather
        // than one up to fifteen seconds old.
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }
}
