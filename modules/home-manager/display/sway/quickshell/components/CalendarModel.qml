import QtQuick
import Quickshell.Io

// Months and events, read from khal. Non-visual, and shared: both the
// standing desktop widget (Calendar.qml) and the panel's calendar pane
// render this. There is one khal parser in this repo and this is it.
//
// vdirsyncer syncs five ICS subscriptions into khal
// (modules/home-manager/calendar-sync.nix); khal merges across all of them,
// so nothing here needs to know how many there are.
//
// One fetch per displayed month, covering the leading and trailing days the
// grid shows, so paging a month is one subprocess and selecting a day is
// none.
Item {
    id: root

    // Drives the pollers. The desktop widget sets it true and leaves it;
    // the panel binds it to being open.
    property bool active: true

    property date today: new Date()
    property date viewMonth: new Date()      // any day in the displayed month
    property date selected: new Date()

    readonly property var monthNames: ["January", "February", "March", "April",
        "May", "June", "July", "August", "September", "October", "November",
        "December"]

    readonly property string monthLabel:
        monthNames[viewMonth.getMonth()] + " " + viewMonth.getFullYear()

    // { "YYYY-MM-DD": [event, ...] }, every event in the fetched window.
    property var eventsByDate: ({})

    function key(d) {
        const m = d.getMonth() + 1, day = d.getDate();
        return d.getFullYear() + "-" + (m < 10 ? "0" : "") + m
             + "-" + (day < 10 ? "0" : "") + day;
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate();
    }

    readonly property var eventsForSelected: eventsByDate[key(selected)] || []

    // On TODAY, what is left of it. A list whose first two entries are
    // lectures you already sat through is a worse answer to "what is coming"
    // than no list at all. Any other day shows the whole day, because there
    // is no "now" in it to be past.
    //
    // All-day entries stay: they are still true at any hour.
    readonly property var upcomingToday: {
        const now = new Date();
        return (eventsByDate[key(now)] || []).filter(e =>
            e["all-day"] === "True" || eventDateTime(e) >= now);
    }

    readonly property var visibleEvents:
        sameDay(selected, today) ? upcomingToday : eventsForSelected

    // Whether today had anything at all, which is what separates "nothing
    // was ever on" from "it has all happened".
    readonly property bool todayHadEvents:
        (eventsByDate[key(today)] || []).length > 0

    // The grid: six weeks from the Monday on or before the 1st, each cell
    // carrying everything the renderer needs so neither renderer repeats
    // this arithmetic.
    readonly property var monthCells: {
        const first = new Date(viewMonth.getFullYear(), viewMonth.getMonth(), 1);
        const lead = (first.getDay() + 6) % 7;          // Monday-first
        const start = new Date(first);
        start.setDate(1 - lead);

        const cells = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(start);
            d.setDate(start.getDate() + i);
            if (i >= 35 && d.getMonth() !== viewMonth.getMonth()) break;
            cells.push({
                day: d.getDate(),
                date: d,
                inMonth: d.getMonth() === viewMonth.getMonth(),
                isToday: sameDay(d, today),
                isSelected: sameDay(d, selected),
                hasEvents: (eventsByDate[key(d)] || []).length > 0
            });
        }
        return cells;
    }

    // Kept for the desktop widget, which shows what is coming rather than a
    // chosen day: the next few events from now, across the fetched window.
    property int upcomingCount: 2
    readonly property var upcomingEvents: {
        const now = new Date();
        const all = [];
        for (const k in eventsByDate)
            for (const e of eventsByDate[k]) all.push(e);
        const future = all.filter(e =>
            e["all-day"] === "True" ? e["start-date"] >= key(now)
                                    : eventDateTime(e) >= now);
        future.sort((a, b) => eventDateTime(a) - eventDateTime(b));
        return future.slice(0, upcomingCount);
    }

    // ---------------- navigation ----------------

    function shiftMonth(n) {
        viewMonth = new Date(viewMonth.getFullYear(), viewMonth.getMonth() + n, 1);
        refresh();
    }
    function selectDay(d) {
        selected = d;
        if (d.getMonth() !== viewMonth.getMonth()
            || d.getFullYear() !== viewMonth.getFullYear()) {
            viewMonth = new Date(d.getFullYear(), d.getMonth(), 1);
            refresh();
        }
    }
    function goToday() {
        const now = new Date();
        today = now;
        selected = now;
        viewMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        refresh();
    }
    readonly property bool onToday:
        sameDay(selected, today)
        && viewMonth.getMonth() === today.getMonth()
        && viewMonth.getFullYear() === today.getFullYear()

    // ---------------- khal ----------------

    function eventDateTime(e) {
        if (e["all-day"] === "True") return new Date(e["start-date"] + "T00:00");
        return new Date(e["start-date"] + "T" + e["start-time"]);
    }

    function eventLabel(e) {
        if (e["all-day"] === "True") return e["title"];
        return e["start-time"] + "  " + e["title"];
    }

    // Multiple synced calendars can carry the same invite - a shared event
    // copied into two subscriptions - so collapse twins keyed on title plus
    // start, keeping the first seen.
    function dedupeEvents(events) {
        const seen = new Set();
        const out = [];
        for (const e of events) {
            const k = e["title"] + "|" + e["start-date"] + "|"
                + (e["all-day"] === "True" ? "allday" : e["start-time"]);
            if (seen.has(k)) continue;
            seen.add(k);
            out.push(e);
        }
        return out;
    }

    // The window we last fetched, and when. khal takes ~0.5s and then two
    // hundred events are parsed here on the GUI thread, so paying that on
    // every single open - for a diary that changes a few times a day - is
    // the most expensive thing the panel does for the least reason.
    property string fetchedWindow: ""
    property real fetchedAt: 0
    readonly property int freshMs: 120000

    function refreshIfStale() {
        const want = windowStart();
        if (want === fetchedWindow && Date.now() - fetchedAt < freshMs) return;
        refresh();
    }

    function windowStart() {
        const first = new Date(viewMonth.getFullYear(), viewMonth.getMonth(), 1);
        const lead = (first.getDay() + 6) % 7;
        const start = new Date(first);
        start.setDate(1 - lead);
        return key(start);
    }

    function refresh() {
        // From the Monday before the 1st, far enough to cover six weeks.
        const first = new Date(viewMonth.getFullYear(), viewMonth.getMonth(), 1);
        const lead = (first.getDay() + 6) % 7;
        const start = new Date(first);
        start.setDate(1 - lead);
        khalProc.command = [
            "khal", "list",
            "--json", "start-date", "--json", "start-time", "--json", "all-day",
            "--json", "title", "--json", "location",
            key(start), "42d"
        ];
        fetchedWindow = key(start);
        fetchedAt = Date.now();
        khalProc.running = true;
    }

    Process {
        id: khalProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(l => l.trim().length > 0);
                let events = [];
                for (const line of lines) {
                    try { events = events.concat(JSON.parse(line)); } catch (e) {}
                }
                events = root.dedupeEvents(events);

                // A khal that is missing, unconfigured or simply has nothing
                // in the window all land here with an empty list, and that
                // is a legitimate answer: the grid still draws.
                const by = {};
                for (const e of events) {
                    const k = e["start-date"];
                    if (!by[k]) by[k] = [];
                    by[k].push(e);
                }
                for (const k in by)
                    by[k].sort((a, b) => root.eventDateTime(a) - root.eventDateTime(b));
                root.eventsByDate = by;
            }
        }
        onExited: exitCode => {
            // khal absent or erroring: an empty month, never a stuck one.
            if (exitCode !== 0) root.eventsByDate = ({});
        }
    }

    Timer {
        interval: 60 * 60 * 1000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.today = new Date();
            root.refreshIfStale();
        }
    }
}
