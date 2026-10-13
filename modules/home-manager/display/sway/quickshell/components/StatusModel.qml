pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// Non-visual data layer for the oserv status widget. Owns both pollers, all
// parsing, and the single place that decides what state a service is in.
// StatusPanel.qml renders this and holds no fetch logic of its own.
Item {
    id: root

    // ---------------- outputs ----------------

    property var services: []
    property bool online: false
    property string verdictText: "No route to oserv"
    property string verdictCount: "—"
    property string hostLoad: "—"
    property string hostRam: "—"
    property string hostDisk: "—"

    // ---------------- tuning ----------------

    // Gatus probes every 15s server-side, so polling faster than this only
    // re-reads identical data.
    readonly property int statusIntervalMs: 10000
    readonly property int metricsIntervalMs: 20000
    // Past this with no successful status fetch, stop trusting what we have.
    readonly property int stalenessMs: 35000

    property double lastOkAt: 0

    // ---------------- presentation list ----------------

    // The widget's own list, deliberately separate from the server's probe
    // list. `promGroup` bridges the Gatus key to process-exporter's groupname
    // label: four of the eight names differ, so this map is mandatory rather
    // than a nicety, and the group cannot be derived from the key. Those
    // matcher names are load-bearing for the existing Grafana dashboard and
    // must not be renamed to match.
    readonly property var labels: ({
        "media_jellyfin":    { label: "Jellyfin",    order: 1, promGroup: "jellyfin" },
        "media_immich":      { label: "Immich",      order: 2, promGroup: "immich-server" },
        "media_immich-ml":   { label: "Immich ML",   order: 3, promGroup: "immich-machine-learning" },
        "files_samba":       { label: "Samba",       order: 4, promGroup: "samba-smbd" },
        "web_caddy":         { label: "Caddy",       order: 5, promGroup: "caddy" },
        "web_grafana":       { label: "Grafana",     order: 6, promGroup: "grafana" },
        "dev_wakapi":        { label: "Wakapi",      order: 7, promGroup: "wakapi" },
        "files_qbittorrent": { label: "qBittorrent", order: 8, promGroup: "qbittorrent" },
        // Appended rather than slotted next to Wakapi: `order` fixes the band
        // positions, and renumbering would move every band you have already
        // learned to read.
        "dev_joplin":        { label: "Joplin",      order: 9, promGroup: "joplin" }
    })

    // groupname -> { cpu, ram }, rebuilt on every metrics poll.
    property var metrics: ({})

    // The widget must be visible from the first frame - before any fetch has
    // returned, and even if oserv is unreachable at login. The idle square's
    // fill *is* the band list, so an empty list draws nothing at all: the
    // "unknown" state, whose whole purpose is to say "I don't know" rather
    // than disappear, would render as no widget. goOffline() maps over the
    // existing rows, so an empty list also never recovers on its own.
    //
    // Seeding from the label map also fixes the band count from the start, so
    // the spine does not reflow when the first payload lands.
    Component.onCompleted: {
        const seeded = []
        for (const key in root.labels) {
            const meta = root.labels[key]
            seeded.push({
                key: key, label: meta.label, order: meta.order,
                state: "unknown", ms: 0, history: [], cpu: "", ram: ""
            })
        }
        seeded.sort(function (a, b) { return a.order - b.order })
        root.services = seeded
    }

    // ---------------- state derivation ----------------

    // Conditions are matched on their text, not their index: the server spec
    // fixes the order, but an accidental reordering there should degrade
    // gracefully instead of silently inverting up and down.
    function stateFor(result) {
        if (!result)
            return "unknown"

        const conds = result.conditionResults || []
        let reach = null
        let timing = null

        for (let i = 0; i < conds.length; i++) {
            const text = conds[i].condition || ""
            if (text.indexOf("STATUS") >= 0 || text.indexOf("CONNECTED") >= 0)
                reach = conds[i].success
            else if (text.indexOf("RESPONSE_TIME") >= 0)
                timing = conds[i].success
        }

        if (reach === false)
            return "down"
        if (timing === false)
            return "degraded"
        // No conditions reported at all: fall back to the overall flag.
        if (reach === null && timing === null)
            return result.success ? "up" : "down"
        return result.success ? "up" : "degraded"
    }

    // Every service here idles below 1% CPU, so whole-percent rounding prints
    // "cpu 0%" across the board and tells you nothing. One decimal under 1%
    // keeps the column narrow while still showing which service is busy.
    function formatPercent(pct) {
        if (pct <= 0)
            return "0%"
        if (pct < 1)
            return pct.toFixed(1) + "%"
        return Math.round(pct) + "%"
    }

    function formatBytes(bytes) {
        if (!(bytes > 0))
            return ""
        if (bytes >= 1073741824)
            return (bytes / 1073741824).toFixed(1) + "G"
        return Math.round(bytes / 1048576) + "M"
    }

    // ---------------- Gatus poller ----------------

    Process {
        id: statusProc
        command: [
            "curl", "-s", "--max-time", "4", "@statusApiUrl@"
        ]

        stdout: StdioCollector {
            onStreamFinished: root.ingestStatus(this.text)
        }

        // A non-zero exit means curl never got a usable response: no route,
        // DNS failure, timeout. That is `unknown`, never `down`.
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.goOffline()
        }
    }

    function ingestStatus(text) {
        let payload = null
        try {
            payload = JSON.parse(text)
        } catch (e) {
            goOffline()
            return
        }

        if (!Array.isArray(payload) || payload.length === 0) {
            goOffline()
            return
        }

        const next = payload.map(function (entry) {
            const key = entry.key || ""
            const meta = root.labels[key] || null
            const results = Array.isArray(entry.results) ? entry.results : []
            // An endpoint added server-side but not yet probed has no results
            // at all - reading [length - 1] off an empty array would yield
            // undefined, so guard rather than index blindly.
            const last = results.length > 0 ? results[results.length - 1] : null
            const group = meta ? meta.promGroup : key
            const m = root.metrics[group] || null

            return {
                key: key,
                label: meta ? meta.label : (entry.name || key),
                order: meta ? meta.order : 99,
                state: root.stateFor(last),
                ms: last ? Math.round(last.duration / 1e6) : 0,
                history: results.map(function (r) {
                    return { success: !!r.success, ms: r.duration / 1e6 }
                }),
                cpu: m ? m.cpu : "",
                ram: m ? m.ram : ""
            }
        })

        // The API returns its array sorted by key, not in server config order,
        // so band positions come from our own `order` - that is what lets a
        // red band mean "that service" at a glance.
        next.sort(function (a, b) {
            return a.order - b.order || a.label.localeCompare(b.label)
        })

        root.services = next
        root.online = true
        root.lastOkAt = Date.now()
        root.recomputeVerdict()
    }

    function goOffline() {
        root.online = false
        // Keep the rows so the panel does not reflow to empty, but blank every
        // state and number - a stale latency shown next to a grey band reads
        // as live data.
        root.services = root.services.map(function (s) {
            return {
                key: s.key, label: s.label, order: s.order,
                state: "unknown", ms: 0, history: [], cpu: "", ram: ""
            }
        })
        root.verdictText = "No route to oserv"
        root.verdictCount = "—"
        root.hostLoad = "—"
        root.hostRam = "—"
        root.hostDisk = "—"
    }

    function recomputeVerdict() {
        let up = 0, down = 0, degraded = 0
        for (let i = 0; i < services.length; i++) {
            const st = services[i].state
            if (st === "up") up++
            else if (st === "down") down++
            else if (st === "degraded") degraded++
        }

        verdictCount = up + "/" + services.length

        if (down > 0)
            verdictText = down === 1 ? "1 service down" : down + " services down"
        else if (degraded > 0)
            verdictText = degraded === 1 ? "1 service slow" : degraded + " services slow"
        else
            verdictText = "All systems up"
    }

    // ---------------- Prometheus poller ----------------

    // One instant query for everything, with every series carrying an explicit
    // `slot` label that says which value it is.
    //
    // The tag is not cosmetic. PromQL's `or` matches series by their label
    // signature *excluding __name__*, so two computed series that reduce to
    // the same remaining labels collide and the right-hand one is silently
    // dropped - node_load1 and a bare host-memory ratio both reduce to
    // {instance, job}, and the memory value vanished from the response with
    // no error. Tagging makes the discriminator explicit instead of depending
    // on which labels a metric happens to carry.
    //
    // CPU is summed by groupname because process-exporter splits
    // cpu_seconds_total by mode (user/system); without the sum each service
    // yields two series and only one of them survives into the display.
    //
    // The [1m] rate window needs at least two samples: the process job is
    // scraped every 15s server-side specifically so this works. Do not widen
    // it assuming the host's global 1m scrape_interval applies here.
    readonly property string promQuery:
        'label_replace(sum by (groupname) (rate(namedprocess_namegroup_cpu_seconds_total[1m])),"slot","cpu","","")'
        + ' or label_replace(sum by (groupname) (namedprocess_namegroup_memory_bytes{memtype="resident"}),"slot","ram","","")'
        + ' or label_replace(node_load1,"slot","load","","")'
        + ' or label_replace(1-(node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes),"slot","mem","","")'
        + ' or label_replace(1-(node_filesystem_avail_bytes{mountpoint="/"}/node_filesystem_size_bytes{mountpoint="/"}),"slot","disk","","")'

    Process {
        id: metricsProc
        // -G with --data-urlencode puts the query in the query string
        // correctly escaped; hand-building the URL would break on the braces
        // and quotes in the PromQL.
        command: [
            "curl", "-s", "--max-time", "4", "-G",
            "--data-urlencode", "query=" + root.promQuery,
            "@metricsApiUrl@"
        ]

        stdout: StdioCollector {
            onStreamFinished: root.ingestMetrics(this.text)
        }

        // Resource numbers are supporting detail. Losing them must not flip
        // the widget offline - that verdict belongs to Gatus alone.
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.clearMetrics()
        }
    }

    // Prometheus can fail while Gatus stays healthy, in three ways: a non-zero
    // curl exit, an unparseable body, or a well-formed {"status":"error"}
    // returned with HTTP 200 (curl exits 0, so onExited never sees it). In
    // every case the resource layer blanks rather than keeping the last good
    // numbers on screen as though they were live - the same rule the
    // transport `unknown` state enforces for reachability. Reachability
    // itself is untouched: that verdict belongs to Gatus alone.
    function clearMetrics() {
        root.metrics = ({})
        root.hostLoad = "—"
        root.hostRam = "—"
        root.hostDisk = "—"
        root.services = root.services.map(function (s) {
            return {
                key: s.key, label: s.label, order: s.order,
                state: s.state, ms: s.ms, history: s.history,
                cpu: "", ram: ""
            }
        })
    }

    function ingestMetrics(text) {
        let payload = null
        try {
            payload = JSON.parse(text)
        } catch (e) {
            root.clearMetrics()
            return
        }

        if (!payload || payload.status !== "success" || !payload.data) {
            root.clearMetrics()
            return
        }

        const rows = payload.data.result || []
        const byGroup = ({})

        for (let i = 0; i < rows.length; i++) {
            const metric = rows[i].metric || {}
            const slot = metric.slot || ""
            const value = parseFloat((rows[i].value || [])[1])
            if (isNaN(value))
                continue

            if (slot === "load") {
                root.hostLoad = value.toFixed(2)
            } else if (slot === "mem") {
                root.hostRam = Math.round(value * 100) + "%"
            } else if (slot === "disk") {
                root.hostDisk = Math.round(value * 100) + "%"
            } else if (slot === "cpu" || slot === "ram") {
                const group = metric.groupname || ""
                if (group === "")
                    continue
                if (!byGroup[group])
                    byGroup[group] = { cpu: "", ram: "" }
                if (slot === "cpu")
                    byGroup[group].cpu = "cpu " + root.formatPercent(value * 100)
                else
                    byGroup[group].ram = "ram " + root.formatBytes(value)
            }
        }

        root.metrics = byGroup

        // Fold the fresh numbers into the rows already on screen rather than
        // waiting for the next status poll.
        root.services = root.services.map(function (s) {
            const meta = root.labels[s.key] || null
            const m = byGroup[meta ? meta.promGroup : s.key] || null
            return {
                key: s.key, label: s.label, order: s.order,
                state: s.state, ms: s.ms, history: s.history,
                cpu: m && root.online ? m.cpu : "",
                ram: m && root.online ? m.ram : ""
            }
        })
    }

    // ---------------- schedulers ----------------

    Timer {
        interval: root.statusIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statusProc.running = true
    }

    Timer {
        interval: root.metricsIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: metricsProc.running = true
    }

    // Guards against a curl that neither fails nor returns: without this, the
    // last good payload would sit on screen looking live forever.
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            if (root.online && root.lastOkAt > 0
                && Date.now() - root.lastOkAt > root.stalenessMs)
                root.goOffline()
        }
    }
}
