# oserv Status Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bottom-left Quickshell widget to the `personal` sway profile that shows live health of the eight services on `oserv`: an ambient rounded square whose colour is the global verdict, growing on hover into a summary pill, then into a per-service detail panel.

**Architecture:** Three new QML components join the existing always-running `quickshell-widgets` service alongside `Wallpaper`/`Clock`/`Music`/`Calendar`/`Lock`/`LaserBar`. `StatusModel.qml` is a non-visual data layer owning two `Process`+`curl` pollers (Gatus for reachability, Prometheus for resources), the JSON parsing, and the state derivation. `StatusPanel.qml` is the `PanelWindow` and all three hover stages. `Sparkline.qml` draws per-row recent history. Endpoint URLs and semantic colours arrive as `@token@` substitutions through the existing `modules/lib/qml-theme.nix`, so no hostname or hex literal lives in QML.

**Tech Stack:** Nix (home-manager), QML (Quickshell, Qt6 `Canvas`), `curl`, sway.

**Spec:** `docs/superpowers/specs/2026-10-09-oserv-status-api-design.md` — that spec is the *server* side. It defines the API contract this widget consumes (section 3, frozen). The widget's own visual design was approved in conversation against the interactive mockup; its decisions are restated as Global Constraints below so this plan stands alone.

## Global Constraints

- The widget is **read-only**. It never writes, restarts, or acts on a service. No `systemctl`, no POST.
- Gatus `duration` is **nanoseconds** — divide by `1e6` for milliseconds. Never assume milliseconds.
- Gatus `key` (`{group}_{name}`) is the only join key. Never join on display name.
- `conditionResults` order is fixed by the spec: index 0 is the status/connected condition, index 1 is response time. Derive state by inspecting the condition *text*, not the index, so a server-side reordering degrades gracefully rather than silently inverting states.
- Three service states plus one transport state: `up`, `degraded`, `down`, and `unknown`. **`unknown` must never render as `down`** — unreachable is dimmed grey, never red.
- "Up" is Horizon's teal, **not `@greenColor@`/`base0B`** — that slot is a peach (`#EFAF8E`) in Horizon dark and is too close to the red to read at band size.
- Teal is **`base0C` in Horizon dark but `base0E` in Horizon light**. Semantic colours are therefore selected by `config.stylix.polarity` in Nix, the same way `laserColor` already is — not by picking one base16 slot.
- Animation durations: square→pill 190ms, pill→panel 210ms, both `Easing.OutCubic`. Do not lengthen these to fix a render artifact.
- The Gatus API returns its array **sorted by key**, not in server config
  order (verified: `dev_wakapi` first, `web_grafana` last). Never positionally
  index into it. The widget's own `order` field is what fixes band positions,
  which is what lets a red band mean "that service" at a glance.
- The key-to-`promGroup` join table is **verified against the live server**;
  four of the eight names differ, so the explicit map is mandatory rather than
  a nicety. Do not "simplify" it by deriving the group from the key.
- Service count ceiling for the spine is 8. Bands below ~2px stop being readable.
- No new systemd service — the widget lives inside the existing `quickshell-widgets` service via `shell.qml`'s `Scope`.
- sway / `personal` profile only. No Hyprland, i3, or `oserv` changes.
- The widget must not reserve screen space or steal focus: `exclusionMode: ExclusionMode.Ignore`, `focusable: false`, and a `mask` confined to the widget's own rectangle so clicks pass through everywhere else.
- The spec's section 3.2 lists the five PromQL queries separately; this plan
  batches them into **one** instant query joined with `or`, with `label_replace`
  re-tagging the computed series so each self-identifies. This is a deliberate
  refinement, not a contradiction: same endpoint, same path restriction, one
  round trip instead of five. The server side is unaffected.
- New arguments added to `modules/lib/qml-theme.nix` **must have defaults**. That file is also called by `modules/nixosconf/greetd.nix` and by the `lockVariant` helper; a required argument breaks both.

## Review Focus

- **Server unreachable, or `curl` exits non-zero** → every band and row goes `unknown` (dimmed grey), the verdict reads "No route to oserv", and nothing renders red. Covered in Task 2 Step 8 and Task 5 Step 2.
- **Malformed or empty JSON** (Gatus mid-restart returning `[]` or an HTML error page) → `JSON.parse` must not throw an uncaught exception that kills the QML scene. Falls back to `unknown`. Covered in Task 2 Step 9.
- **A service present in the API but absent from the widget's label map** (you added one server-side) → renders with its Gatus `name`, sorted last, with no CPU/RAM. Must not drop the row or crash. Covered in Task 2 Step 10.
- **An endpoint whose `results` array is empty** (just added server-side, never probed) → treated as `unknown`, not as a success, and `results[length-1]` must not be read off the end. Covered in Task 2 Step 11.
- **Stale-but-successful data** (last fetch succeeded 5 minutes ago, `curl` now hanging) → after 35s with no fresh response the widget degrades to `unknown` rather than showing confidently wrong green. Covered in Task 5 Step 4.

---

## File Structure

- Modify: `modules/lib/qml-theme.nix` — add the semantic status colour tokens and the two API URL tokens, all as defaulted arguments.
- Modify: `modules/home-manager/display/sway/quickshell/default.nix` — accept `cfg`, derive the polarity-correct status colours, build the API URLs from `cfg.server.domain`, register the three new QML files.
- Create: `modules/home-manager/display/sway/quickshell/components/StatusModel.qml` — non-visual: both pollers, JSON parsing, state derivation, the key→label map. Exposes `services`, `online`, `verdictText`, `verdictCount`, `hostLoad`, `hostRam`, `hostDisk`.
- Create: `modules/home-manager/display/sway/quickshell/components/Sparkline.qml` — a `Canvas` that draws one service's recent success/latency history.
- Create: `modules/home-manager/display/sway/quickshell/components/StatusPanel.qml` — the `PanelWindow`, the health spine, the three hover stages, the rows, the host footer.
- Modify: `modules/home-manager/display/sway/quickshell/shell.qml` — add `StatusPanel {}` to the `Scope`.

Task 1 is Nix-only and lands the plumbing. Task 2 is the data layer, verifiable against a local fixture server with no dependency on `oserv` being built yet. Task 3 renders the panel at its fullest stage only, so layout is reviewed separately from interaction. Task 4 adds the three-stage behaviour. Task 5 validates the states and both polarities on real hardware.

---

### Task 1: Nix plumbing — tokens, URLs, registration

**Files:**
- Modify: `modules/lib/qml-theme.nix`
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`

**Interfaces:**
- Consumes: nothing.
- Produces: the `@token@` names every later task writes into QML — `@statusApiUrl@`, `@metricsApiUrl@`, `@upColor@`, `@degradedColor@`, `@downColor@`, `@unknownColor@`, `@panelBg@`, `@panelBorder@`, `@nameColor@`, `@mutedColor@`. Also the registered config paths `quickshell/widgets/components/{StatusModel,Sparkline,StatusPanel}.qml`.

- [ ] **Step 1: Add the new tokens to `modules/lib/qml-theme.nix`**

Change the function signature. The five new arguments all take defaults so the
other two callers (`modules/nixosconf/greetd.nix` and the `lockVariant` helper
in the quickshell module) keep working untouched — they do not use these
tokens.

```nix
{ colors
, laserColor
, lockscreenImage
, systemctlBin
, corptaFontPath
  # Status-widget tokens. Defaulted so greetd.nix and lockVariant, which
  # never render StatusPanel.qml, do not have to pass them. The colour
  # defaults are the Horizon *dark* values; the quickshell module always
  # passes explicit polarity-correct values, so these only ever apply to
  # surfaces that do not use the tokens at all.
, statusApiUrl ? ""
, metricsApiUrl ? ""
, upColor ? "#FF24A8B4"
, degradedColor ? "#FFEFB993"
, downColor ? "#FFE93C58"
}:
```

Then add to the search list, in this order, appended after `"@corptaFontPath@"`:

```nix
    "@statusApiUrl@"
    "@metricsApiUrl@"
    "@upColor@"
    "@degradedColor@"
    "@downColor@"
    "@unknownColor@"
    "@panelBg@"
    "@panelBorder@"
    "@nameColor@"
    "@mutedColor@"
```

and the matching replacements, in the same order, appended after
`corptaFontPath`:

```nix
    statusApiUrl
    metricsApiUrl
    upColor
    degradedColor
    downColor
    "#FF${colors.base03}"
    "#B3${colors.base00}"
    "#33${colors.base05}"
    "#FF${colors.base05}"
    "#FF${colors.base04}"
```

`builtins.replaceStrings` pairs the two lists positionally — a token added to
one list and not the other at the same index silently substitutes the wrong
value. Count both lists after editing.

- [ ] **Step 2: Derive the polarity-correct colours and URLs in `default.nix`**

Add `cfg` to the module arguments (the signature already ends in `...`, so this
is additive):

```nix
{ cfg, pkgs, upkgs, config, lib, ... }:
```

In the `let` block, after the existing `laserColor` binding:

```nix
  # Horizon puts teal at base0C in the dark scheme but base0E in the light
  # one, and base0C in light is a red-orange - so a single base16 slot
  # cannot mean "up" in both. Selected by polarity instead, exactly like
  # laserColor above. The light teal is the darker #1D8991 so a filled band
  # still clears 3:1 against the light ground.
  isLight = config.stylix.polarity == "light";

  statusColors = {
    upColor = if isLight then "#FF1D8991" else "#FF24A8B4";
    degradedColor = if isLight then "#FFF6661E" else "#FFEFB993";
    downColor = if isLight then "#FFDA103F" else "#FFE93C58";
  };

  # Built from cfg.server.domain so the tailnet hostnames are never
  # hardcoded in QML. cfg-perso embeds the server profile under .server
  # (see host/profiles.nix).
  statusApiUrl = "http://status.tail.${cfg.server.domain}/api/v1/endpoints/statuses";
  metricsApiUrl = "http://metrics.tail.${cfg.server.domain}/api/v1/query";
```

Then extend the `barTheme` call to pass them:

```nix
  barTheme = qmlTheme ({
    inherit colors laserColor systemctlBin corptaFontPath;
    inherit statusApiUrl metricsApiUrl;
    lockscreenImage = "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png";
  } // statusColors);
```

Leave the `lockVariant` helper alone — it renders only the lock surfaces and
relies on the new defaults.

- [ ] **Step 3: Register the three new files**

Add to the `xdg.configFile` attrset, after the existing `LaserBar.qml` line:

```nix
    "quickshell/widgets/components/StatusModel.qml" = themedQmlFile ./components/StatusModel.qml;
    "quickshell/widgets/components/Sparkline.qml" = themedQmlFile ./components/Sparkline.qml;
    "quickshell/widgets/components/StatusPanel.qml" = themedQmlFile ./components/StatusPanel.qml;
```

- [ ] **Step 4: Create the three files as stubs so the flake can evaluate**

`builtins.readFile` fails on a missing path, so the files must exist before
`nix flake check` will run.

```bash
cd modules/home-manager/display/sway/quickshell/components
printf 'import QtQuick\n\nItem {}\n' > StatusModel.qml
printf 'import QtQuick\n\nItem {}\n' > Sparkline.qml
printf 'import QtQuick\n\nItem {}\n' > StatusPanel.qml
```

- [ ] **Step 5: Verify the flake evaluates**

Run: `nix flake check`
Expected: exits 0, no error mentioning `qml-theme` or `statusApiUrl`.

- [ ] **Step 6: Verify both replaceStrings lists stayed the same length**

```bash
nix eval --impure --expr '
let t = import ./modules/lib/qml-theme.nix {
      colors = (import ./modules/lib/theme-colors.nix).dark;
      laserColor = "#000000"; lockscreenImage = ""; systemctlBin = "";
      corptaFontPath = "";
    };
in t "@statusApiUrl@|@upColor@|@unknownColor@|@panelBg@|@mutedColor@"'
```

Expected: `"|#FF24A8B4|#FF6F6F70|#B31C1E26|#FF9DA0A2"` — the first field empty
because `statusApiUrl` defaulted to `""`, and every other token resolved to a
real colour. A literal `@upColor@` surviving in the output means the two lists
are misaligned.

- [ ] **Step 7: Confirm the greeter path still renders**

Adding defaulted arguments must not disturb the other callers.

Run: `nix eval --raw .#nixosConfigurations.personal.config.system.build.toplevel.drvPath`
Expected: a `/nix/store/....drv` path, no evaluation error.

- [ ] **Step 8: Commit**

```bash
git add modules/lib/qml-theme.nix \
        modules/home-manager/display/sway/quickshell/default.nix \
        modules/home-manager/display/sway/quickshell/components/StatusModel.qml \
        modules/home-manager/display/sway/quickshell/components/Sparkline.qml \
        modules/home-manager/display/sway/quickshell/components/StatusPanel.qml
git commit -m "feat(status): add theme tokens and registration for the oserv status widget"
```

---

### Task 2: StatusModel.qml — polling, parsing, state derivation

**Files:**
- Modify: `modules/home-manager/display/sway/quickshell/components/StatusModel.qml`
- Create (throwaway, not committed): a fixture directory under
  `/tmp/status-fixtures/api/v1/endpoints/` for offline testing.

**Interfaces:**
- Consumes: `@statusApiUrl@`, `@metricsApiUrl@` from Task 1.
- Produces, read by Tasks 3 and 4:
  - `property var services` — array of
    `{ key: string, label: string, state: string, ms: int, history: array, cpu: string, ram: string }`,
    where `state` is one of `"up" | "degraded" | "down" | "unknown"`, `history`
    is an array of `{ success: bool, ms: real }` oldest-first, and `cpu`/`ram`
    are preformatted display strings or `""`.
  - `property bool online`
  - `property string verdictText`, `property string verdictCount`
  - `property string hostLoad`, `property string hostRam`, `property string hostDisk`

- [ ] **Step 1: Write the full component**

Replace the stub with:

```qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// Non-visual data layer for the oserv status widget. Owns both pollers,
// all parsing, and the single place that decides what state a service is
// in. StatusPanel.qml renders this and holds no fetch logic of its own.
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

    // Gatus probes every 15s server-side (see the server spec), so polling
    // faster than this only re-reads identical data.
    readonly property int statusIntervalMs: 10000
    readonly property int metricsIntervalMs: 20000
    // Past this with no successful status fetch, stop trusting what we have.
    readonly property int stalenessMs: 35000

    property double lastOkAt: 0

    // ---------------- presentation list ----------------

    // The widget's own list, deliberately separate from the server's probe
    // list. `promGroup` bridges the Gatus key to process-exporter's
    // groupname label where the two names differ; those matcher names are
    // load-bearing for the existing Grafana dashboard and must not be
    // renamed to match.
    readonly property var labels: ({
        "media_jellyfin":       { label: "Jellyfin",    order: 1, promGroup: "jellyfin" },
        "media_immich":         { label: "Immich",      order: 2, promGroup: "immich-server" },
        "media_immich-ml":      { label: "Immich ML",   order: 3, promGroup: "immich-machine-learning" },
        "files_samba":          { label: "Samba",       order: 4, promGroup: "samba-smbd" },
        "web_caddy":            { label: "Caddy",       order: 5, promGroup: "caddy" },
        "web_grafana":          { label: "Grafana",     order: 6, promGroup: "grafana" },
        "dev_wakapi":           { label: "Wakapi",      order: 7, promGroup: "wakapi" },
        "files_qbittorrent":    { label: "qBittorrent", order: 8, promGroup: "qbittorrent" }
    })

    // groupname -> { cpu, ram }, rebuilt on every metrics poll.
    property var metrics: ({})

    // ---------------- state derivation ----------------

    // Conditions are matched on their text, not their index: the server
    // spec fixes the order, but an accidental reordering there should
    // degrade gracefully instead of silently inverting up and down.
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
            // An endpoint added server-side but not yet probed has no
            // results at all - reading [length - 1] off an empty array
            // would yield undefined, so guard rather than index blindly.
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
        // Keep the rows so the panel does not reflow to empty, but blank
        // every state and number - a stale latency shown next to a grey
        // band reads as live data.
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

    // One instant query for everything. rate() and arithmetic both drop
    // __name__, so the computed series are re-tagged with label_replace -
    // that way every series in the union self-identifies and the response
    // can be demultiplexed by metric name alone.
    readonly property string promQuery:
        'label_replace(rate(namedprocess_namegroup_cpu_seconds_total[1m]),"__name__","svc_cpu","","")'
        + ' or namedprocess_namegroup_memory_bytes{memtype="resident"}'
        + ' or node_load1'
        + ' or label_replace(1-(node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes),"__name__","host_mem","","")'
        + ' or label_replace(1-(node_filesystem_avail_bytes{mountpoint="/"}/node_filesystem_size_bytes{mountpoint="/"}),"__name__","host_disk","","")'

    Process {
        id: metricsProc
        // -G with --data-urlencode puts the query in the query string
        // correctly escaped; hand-building the URL would break on the
        // braces and quotes in the PromQL.
        command: [
            "curl", "-s", "--max-time", "4", "-G",
            "--data-urlencode", "query=" + root.promQuery,
            "@metricsApiUrl@"
        ]

        stdout: StdioCollector {
            onStreamFinished: root.ingestMetrics(this.text)
        }

        // Resource numbers are supporting detail. Losing them must not
        // flip the widget offline - that verdict belongs to Gatus alone.
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.metrics = ({})
        }
    }

    function ingestMetrics(text) {
        let payload = null
        try {
            payload = JSON.parse(text)
        } catch (e) {
            root.metrics = ({})
            return
        }

        if (!payload || payload.status !== "success" || !payload.data)
            return

        const rows = payload.data.result || []
        const byGroup = ({})

        for (let i = 0; i < rows.length; i++) {
            const metric = rows[i].metric || {}
            const name = metric.__name__ || ""
            const value = parseFloat((rows[i].value || [])[1])
            if (isNaN(value))
                continue

            if (name === "node_load1") {
                root.hostLoad = value.toFixed(2)
            } else if (name === "host_mem") {
                root.hostRam = Math.round(value * 100) + "%"
            } else if (name === "host_disk") {
                root.hostDisk = Math.round(value * 100) + "%"
            } else if (name === "svc_cpu" || name === "namedprocess_namegroup_memory_bytes") {
                const group = metric.groupname || ""
                if (group === "")
                    continue
                if (!byGroup[group])
                    byGroup[group] = { cpu: "", ram: "" }
                if (name === "svc_cpu")
                    byGroup[group].cpu = "cpu " + Math.round(value * 100) + "%"
                else
                    byGroup[group].ram = "ram " + root.formatBytes(value)
            }
        }

        root.metrics = byGroup

        // Fold the fresh numbers into the rows already on screen rather
        // than waiting for the next status poll.
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

    // Guards against a curl that neither fails nor returns: without this,
    // the last good payload would sit on screen looking live forever.
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
```

- [ ] **Step 2: Verify the flake still evaluates**

Run: `nix flake check`
Expected: exits 0.

- [ ] **Step 3: Confirm every token was substituted**

```bash
nix eval --raw '.#homeConfigurations.personal.config.xdg.configFile."quickshell/widgets/components/StatusModel.qml".text' \
  | grep -oE '@[a-zA-Z]+@' || echo "no leftover tokens"
```

Expected: `no leftover tokens`. A surviving `@statusApiUrl@` means Task 1's
`barTheme` call did not actually receive the argument.

- [ ] **Step 4: Confirm the URL resolved to the real tailnet host**

```bash
nix eval --raw '.#homeConfigurations.personal.config.xdg.configFile."quickshell/widgets/components/StatusModel.qml".text' \
  | grep -n 'status.tail\|metrics.tail'
```

Expected: both hostnames appear with the real domain, no `${` left in them.

- [ ] **Step 5: Build the offline fixture server**

`oserv` has not been rebuilt yet, so test against a local stand-in. This
fixture is throwaway — do not commit it.

```bash
mkdir -p /tmp/status-fixtures/api/v1/endpoints
cat > /tmp/status-fixtures/api/v1/endpoints/statuses <<'JSON'
[
  {"name":"Jellyfin","group":"media","key":"media_jellyfin","results":[
    {"status":200,"duration":40100000,"success":true,"timestamp":"2026-10-09T12:00:00Z",
     "conditionResults":[{"condition":"[STATUS] == 200","success":true},{"condition":"[RESPONSE_TIME] < 300","success":true}]},
    {"status":200,"duration":42318000,"success":true,"timestamp":"2026-10-09T12:00:15Z",
     "conditionResults":[{"condition":"[STATUS] == 200","success":true},{"condition":"[RESPONSE_TIME] < 300","success":true}]}]},
  {"name":"Immich","group":"media","key":"media_immich","results":[
    {"status":0,"duration":0,"success":false,"timestamp":"2026-10-09T12:00:15Z",
     "conditionResults":[{"condition":"[STATUS] == 200","success":false},{"condition":"[RESPONSE_TIME] < 300","success":true}]}]},
  {"name":"Wakapi","group":"dev","key":"dev_wakapi","results":[
    {"status":200,"duration":412000000,"success":false,"timestamp":"2026-10-09T12:00:15Z",
     "conditionResults":[{"condition":"[STATUS] == 200","success":true},{"condition":"[RESPONSE_TIME] < 300","success":false}]}]},
  {"name":"Joplin","group":"web","key":"web_joplin","results":[]}
]
JSON
cd /tmp/status-fixtures && python3 -m http.server 8099 &
```

- [ ] **Step 6: Verify the fixture serves and the shape is what the model expects**

```bash
curl -s http://127.0.0.1:8099/api/v1/endpoints/statuses | python3 -m json.tool | head -5
```

Expected: valid JSON, an array opening with the Jellyfin entry.

- [ ] **Step 7: Render a preview copy pointed at the fixture**

Follow the harness described in `docs/greeter.md` — call the **real**
`modules/lib/qml-theme.nix` so the preview is what a rebuild installs, with
only the URLs swapped to the fixture.

```bash
mkdir -p /tmp/status-preview/components
for f in StatusModel Sparkline StatusPanel; do
  nix eval --impure --raw --expr "
    import ./modules/lib/qml-theme.nix {
      colors = (import ./modules/lib/theme-colors.nix).dark;
      laserColor = \"#000000\"; lockscreenImage = \"\"; systemctlBin = \"/bin/true\";
      corptaFontPath = \"\";
      statusApiUrl = \"http://127.0.0.1:8099/api/v1/endpoints/statuses\";
      metricsApiUrl = \"http://127.0.0.1:8099/api/v1/query\";
      upColor = \"#FF24A8B4\"; degradedColor = \"#FFEFB993\"; downColor = \"#FFE93C58\";
    } (builtins.readFile ./modules/home-manager/display/sway/quickshell/components/$f.qml)
  " > /tmp/status-preview/components/$f.qml
done
grep -roE '@[a-zA-Z]+@' /tmp/status-preview/ || echo "no leftover tokens"
```

Expected: `no leftover tokens`.

- [ ] **Step 8: Verify the offline path (Review Focus)**

Point the model at a dead port and confirm it reports `unknown`, not `down`.
Write a throwaway harness that prints the model's outputs:

```bash
cat > /tmp/status-preview/probe.qml <<'QML'
import QtQuick
import Quickshell
import "components"

ShellRoot {
    StatusModel {
        id: statusModel
        Timer {
            interval: 2500; running: true; repeat: false
            onTriggered: {
                console.log("online=" + statusModel.online)
                console.log("verdict=" + statusModel.verdictText + " " + statusModel.verdictCount)
                for (let i = 0; i < statusModel.services.length; i++) {
                    const s = statusModel.services[i]
                    console.log("  " + s.label + " state=" + s.state
                                + " ms=" + s.ms + " hist=" + s.history.length
                                + " cpu=" + s.cpu + " ram=" + s.ram)
                }
                Qt.quit()
            }
        }
    }
}
QML
sed -i 's|http://127.0.0.1:8099|http://127.0.0.1:9|' /tmp/status-preview/components/StatusModel.qml
cd /tmp/status-preview && nix run .#/dev/null 2>/dev/null; quickshell -p /tmp/status-preview/probe.qml
```

If `quickshell` is not on `PATH`, use
`nix shell .#packages.x86_64-linux.default --command quickshell -p /tmp/status-preview/probe.qml`
from the quickshell flake input, or run it after Task 5's switch.

Expected output: `online=false`, `verdict=No route to oserv —`, and no
service reporting `state=down`.

- [ ] **Step 9: Verify malformed JSON does not kill the scene (Review Focus)**

```bash
printf '<html>502 Bad Gateway</html>' > /tmp/status-fixtures/api/v1/endpoints/statuses
sed -i 's|http://127.0.0.1:9|http://127.0.0.1:8099|' /tmp/status-preview/components/StatusModel.qml
quickshell -p /tmp/status-preview/probe.qml
```

Expected: `online=false`, no `TypeError`/`SyntaxError` in the output, process
exits cleanly rather than aborting.

- [ ] **Step 10: Verify an unmapped service still renders (Review Focus)**

Restore the full fixture from Step 5. The `web_joplin` entry is deliberately
absent from the `labels` map.

Expected: a row labelled `Joplin` (its Gatus `name`) appears, sorted last,
with `cpu=` and `ram=` empty, and the process does not error.

- [ ] **Step 11: Verify the empty-results guard (Review Focus)**

Same run as Step 10. The `web_joplin` entry has `"results":[]`.

Expected: `Joplin state=unknown ms=0 hist=0`. Specifically **not** `state=up`,
and no "cannot read property of undefined" error.

- [ ] **Step 12: Verify the three states derive correctly**

Same run, with the full fixture.

Expected: `Jellyfin state=up ms=42`, `Immich state=down`,
`Wakapi state=degraded ms=412`. The Wakapi case is the important one — its
`success` is `false` but its status condition passed, which must read as
degraded rather than down.

- [ ] **Step 13: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/StatusModel.qml
git commit -m "feat(status): add the polling and state-derivation model"
```

---

### Task 3: Sparkline and the panel at full detail

**Files:**
- Modify: `modules/home-manager/display/sway/quickshell/components/Sparkline.qml`
- Modify: `modules/home-manager/display/sway/quickshell/components/StatusPanel.qml`
- Modify: `modules/home-manager/display/sway/quickshell/shell.qml`

**Interfaces:**
- Consumes: everything `StatusModel.qml` produces (Task 2), and the colour
  tokens from Task 1.
- Produces: `StatusPanel`'s internal ids used by Task 4 — `shell` (the root
  visual `Rectangle`), `spineBox` (the `Item` wrapping the health spine), and
  `contentCol`. Task 4 adds the `stage` property and the hover handlers; this
  task renders stage 2 unconditionally.

- [ ] **Step 1: Write `Sparkline.qml`**

```qml
import QtQuick

// One service's recent probe history: a latency line with failed probes
// marked as vertical ticks. Canvas rather than Shape (which BeamSide.qml
// moved to for performance) because this repaints on a 10s poll, not per
// frame - the Canvas cost is irrelevant here and the imperative path is
// far clearer for a polyline plus ticks.
Canvas {
    id: root

    // Array of { success: bool, ms: real }, oldest first.
    property var history: []
    property color lineColor: "@upColor@"
    property color failColor: "@downColor@"

    // Per-row adaptive scale. A fixed ceiling does not work here: measured
    // latencies on oserv run 0.1ms (Samba, a TCP connect) to 35ms (Grafana),
    // so any ceiling high enough to show a 400ms degradation flattens every
    // healthy row onto the baseline - 0.63px of travel on a 13px canvas.
    //
    // The floor stops the opposite failure: Samba's 0.1-0.7ms jitter would
    // otherwise autoscale into dramatic-looking swings. Below the floor a row
    // reads as flat, which is the honest description of "fast and steady",
    // while a genuine 50x regression still clears it and shows up.
    //
    // Failed probes are excluded from the max: a timeout reports the full
    // --max-time as its duration, and letting that set the ceiling would
    // crush all the real measurements against the baseline.
    readonly property real msFloor: 12
    readonly property real msCeiling: {
        let peak = 0
        for (let i = 0; i < history.length; i++) {
            if (history[i].success && history[i].ms > peak)
                peak = history[i].ms
        }
        return Math.max(msFloor, peak * 1.15)
    }

    implicitWidth: 46
    implicitHeight: 13
    renderStrategy: Canvas.Immediate

    onHistoryChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onMsCeilingChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()

        const n = history.length
        if (n === 0)
            return

        const step = n > 1 ? width / (n - 1) : 0

        // Failed probes first, so the line draws over them.
        ctx.fillStyle = root.failColor
        ctx.globalAlpha = 0.45
        for (let i = 0; i < n; i++) {
            if (history[i].success)
                continue
            ctx.fillRect(Math.max(0, i * step - 1.4), 0, 2.8, height)
        }

        if (n < 2)
            return

        ctx.globalAlpha = 0.85
        ctx.strokeStyle = root.lineColor
        ctx.lineWidth = 1.4
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.beginPath()


        for (let i = 0; i < n; i++) {
            const norm = Math.min(1, Math.max(0, history[i].ms / root.msCeiling))
            // A failure pins to the top of the band rather than to a
            // latency of zero, which would otherwise read as "instant".
            const y = history[i].success ? height - 2 - norm * (height - 5) : 1.5
            if (i === 0)
                ctx.moveTo(0, y)
            else
                ctx.lineTo(i * step, y)
        }

        ctx.stroke()
    }
}
```

- [ ] **Step 2: Write `StatusPanel.qml` rendering stage 2 only**

The `stage` property is hardcoded to `2` here so layout can be reviewed on its
own; Task 4 makes it dynamic.

```qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as Components

PanelWindow {
    id: win

    // Stage 2 is the largest extent; the window is sized to it and the
    // widget is drawn in its bottom-left. The mask below keeps input
    // confined to the widget itself so the rest of this window is
    // click-through.
    readonly property int rowHeight: 26
    readonly property int maxServices: 8

    anchors {
        bottom: true
        left: true
    }
    margins {
        bottom: 22
        left: 22
    }

    implicitWidth: 320
    implicitHeight: 380
    color: "transparent"

    WlrLayershell.namespace: "status-widget"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Ignore
    focusable: false

    // Only the widget's own rounded rectangle accepts the pointer.
    // Region follows the item's geometry, so this tracks the growth
    // automatically with no manual recalculation.
    mask: Region {
        item: shell
        radius: shell.radius
    }

    Components.StatusModel {
        // Deliberately not `id: model` - that collides with Repeater's own
        // `model` property, making `model: model.services` resolve against
        // the Repeater rather than this component.
        id: statusModel
    }

    // Stage: 0 = square, 1 = pill, 2 = panel. Fixed in this task.
    property int stage: 2

    readonly property int sq: 22
    readonly property int pillW: 186
    readonly property int pillH: 40
    readonly property int panelW: 302
    // 11 top pad + 18 verdict + 10 rows pad + rows + 27 footer + 10 bottom pad.
    // Math.max guards the moment before the first poll returns, when the
    // service list is empty and the panel would otherwise collapse.
    readonly property int panelH:
        11 + 18 + 10
        + rowHeight * Math.max(1, statusModel.services.length)
        + 27 + 10

    Rectangle {
        id: shell

        anchors.left: parent.left
        anchors.bottom: parent.bottom

        width: win.stage === 0 ? win.sq : win.stage === 1 ? win.pillW : win.panelW
        height: win.stage === 0 ? win.sq : win.stage === 1 ? win.pillH : win.panelH
        radius: win.stage === 0 ? 7 : win.stage === 1 ? 13 : 16

        // At idle the surface drops away entirely and the spine *is* the
        // object, so the verdict colour reads with nothing around it.
        color: win.stage === 0 ? "transparent" : "@panelBg@"
        border.color: win.stage === 0 ? "transparent" : "@panelBorder@"
        border.width: 1

        Row {
            anchors.fill: parent
            anchors.margins: win.stage === 0 ? 0 : 1
            anchors.leftMargin: win.stage === 0 ? 0 : 9
            anchors.rightMargin: win.stage === 0 ? 0 : 13
            anchors.topMargin: win.stage === 0 ? 0 : 11
            anchors.bottomMargin: win.stage === 0 ? 0 : 10
            spacing: win.stage === 0 ? 0 : 11

            // ---- the health spine ----
            // One band per service, fixed order. Collapsed it is the idle
            // square; expanded it is this rail, with every band aligned to
            // its own row. Positions never move between stages, so a red
            // band in the square already says which service broke.
            Item {
                id: spineBox
                width: win.stage === 0 ? win.sq : 5
                height: parent.height

                // At stage 2 the spine must span exactly the rows block, not
                // the whole panel - otherwise the bands drift out of line
                // with their rows and the spine stops meaning anything.
                // 28 = the 18px verdict line plus the rows' 10px top
                // padding; 27 = the footer.
                readonly property int topInset: win.stage === 2 ? 28 : 0
                readonly property int bottomInset: win.stage === 2 ? 27 : 0

                readonly property int count:
                    Math.max(1, statusModel.services.length)
                readonly property real bandH:
                    (height - topInset - bottomInset) / count

                Column {
                    y: spineBox.topInset
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: statusModel.services

                        Item {
                            id: band
                            required property var modelData
                            required property int index

                            width: spineBox.width
                            height: spineBox.bandH

                            Rectangle {
                                anchors.fill: parent
                                // Inset rather than Column spacing: equal
                                // bands separated by gaps would shift every
                                // band's centre off its row's centre. An
                                // inset keeps band n centred exactly on
                                // row n.
                                anchors.topMargin: win.stage === 0 ? 0 : 1
                                anchors.bottomMargin: win.stage === 0 ? 0 : 1

                                // At idle the bands butt together into a
                                // single square, so only the outer corners
                                // round.
                                radius: win.stage === 0 ? 0 : 2
                                topLeftRadius:
                                    win.stage === 0 && band.index === 0 ? 7 : radius
                                topRightRadius:
                                    win.stage === 0 && band.index === 0 ? 7 : radius
                                bottomLeftRadius:
                                    win.stage === 0 && band.index === spineBox.count - 1 ? 7 : radius
                                bottomRightRadius:
                                    win.stage === 0 && band.index === spineBox.count - 1 ? 7 : radius

                                color: band.modelData.state === "up" ? "@upColor@"
                                     : band.modelData.state === "degraded" ? "@degradedColor@"
                                     : band.modelData.state === "down" ? "@downColor@"
                                     : "@unknownColor@"
                                opacity: statusModel.online ? 1.0 : 0.55
                            }
                        }
                    }
                }
            }

            // ---- content column ----
            Column {
                id: contentCol
                width: parent.width - spineBox.width - parent.spacing
                visible: win.stage !== 0
                spacing: 0

                // Verdict line. Stays mounted in stage 2 as the header,
                // which is what makes the pill and the panel feel like one
                // object rather than a swap.
                Item {
                    width: parent.width
                    height: 18

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: statusModel.verdictText
                        color: statusModel.online ? "@nameColor@" : "@mutedColor@"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: statusModel.verdictCount
                        color: "@mutedColor@"
                        font.pixelSize: 11.5
                        font.features: ({ "tnum": 1 })
                    }
                }

                // ---- per-service rows ----
                Column {
                    width: parent.width
                    visible: win.stage === 2
                    spacing: 0
                    topPadding: 10

                    Repeater {
                        model: statusModel.services

                        Item {
                            id: row
                            required property var modelData
                            width: parent.width
                            height: win.rowHeight

                            property bool showResources:
                                rowHover.hovered && statusModel.online
                                && (modelData.cpu !== "" || modelData.ram !== "")

                            HoverHandler { id: rowHover }

                            Rectangle {
                                anchors.fill: parent
                                anchors.rightMargin: -4
                                radius: 5
                                color: rowHover.hovered ? "@panelBorder@" : "transparent"
                            }

                            Text {
                                id: nameText
                                anchors.left: parent.left
                                anchors.leftMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 108
                                elide: Text.ElideRight
                                text: row.modelData.label
                                color: row.modelData.state === "down" ? "@downColor@"
                                     : row.modelData.state === "unknown" ? "@mutedColor@"
                                     : "@nameColor@"
                                font.pixelSize: 12.5
                            }

                            Components.Sparkline {
                                anchors.right: msText.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !row.showResources && row.modelData.history.length > 0
                                history: row.modelData.history
                                lineColor: row.modelData.state === "degraded"
                                    ? "@degradedColor@" : "@upColor@"
                            }

                            Text {
                                id: msText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !row.showResources
                                text: row.modelData.state === "unknown" ? "—"
                                    : row.modelData.state === "down" ? "no reply"
                                    : row.modelData.ms + " ms"
                                color: "@mutedColor@"
                                font.pixelSize: 11.5
                                font.features: ({ "tnum": 1 })
                            }

                            // The second layer, kept out of the way until
                            // the row is actually asked about.
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: row.showResources
                                text: row.modelData.cpu + "  " + row.modelData.ram
                                color: "@mutedColor@"
                                font.pixelSize: 11
                                font.features: ({ "tnum": 1 })
                            }
                        }
                    }
                }

                // ---- host footer ----
                Item {
                    width: parent.width
                    height: 27
                    visible: win.stage === 2

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 9
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: "@panelBorder@"
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.bottom: parent.bottom
                        spacing: 14

                        Text {
                            text: "load " + statusModel.hostLoad
                            color: "@mutedColor@"
                            font.pixelSize: 11.5
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            text: "ram " + statusModel.hostRam
                            color: "@mutedColor@"
                            font.pixelSize: 11.5
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            text: "disk " + statusModel.hostDisk
                            color: "@mutedColor@"
                            font.pixelSize: 11.5
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Add the panel to `shell.qml`**

```qml
import Quickshell
import "components"

Scope {
    Wallpaper {}
    Clock {}
    Music {}
    Calendar {}
    Lock {}
    LaserBar {}
    StatusPanel {}
}
```

- [ ] **Step 4: Verify the flake evaluates**

Run: `nix flake check`
Expected: exits 0.

- [ ] **Step 5: Verify no tokens survived in either new file**

```bash
for f in Sparkline StatusPanel; do
  nix eval --raw ".#homeConfigurations.personal.config.xdg.configFile.\"quickshell/widgets/components/$f.qml\".text" \
    | grep -oE '@[a-zA-Z]+@' && echo "LEFTOVER in $f"
done; echo "checked"
```

Expected: no `LEFTOVER` lines.

- [ ] **Step 6: Render the preview and screenshot stage 2**

Re-render all three files with the Step 7 loop from Task 2 (pointing at the
live fixture server), then run headless and screenshot. Hover is not testable
headless — `docs/greeter.md` documents that a headless seat has no pointer
device — but stage 2 is hardcoded in this task precisely so the layout can be
photographed without one.

```bash
cd /tmp/status-preview
WLR_BACKENDS=headless sway -c /dev/null &
sleep 2
WAYLAND_DISPLAY=wayland-1 quickshell -p /tmp/status-preview/ &
sleep 3
WAYLAND_DISPLAY=wayland-1 grim /tmp/status-stage2.png
```

- [ ] **Step 7: Review the screenshot against the approved design**

Open `/tmp/status-stage2.png` and confirm:
- Each spine band lines up with its own row — band *n*'s vertical centre
  matches row *n*'s. Misalignment here means the spine height or the row
  padding arithmetic is off.
- The Immich row is red with "no reply"; Wakapi is amber with "412 ms".
- Joplin renders last, with no sparkline and no latency.
- Latency numbers are right-aligned and share a column edge.
- The footer divider spans the content column, not the spine.

- [ ] **Step 8: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/Sparkline.qml \
        modules/home-manager/display/sway/quickshell/components/StatusPanel.qml \
        modules/home-manager/display/sway/quickshell/shell.qml
git commit -m "feat(status): render the status panel detail view"
```

---

### Task 4: Three-stage hover interaction

**Files:**
- Modify: `modules/home-manager/display/sway/quickshell/components/StatusPanel.qml`

**Interfaces:**
- Consumes: `shell`, `spineBox`, `contentCol` from Task 3.
- Produces: nothing downstream; this completes the component.

- [ ] **Step 1: Make `stage` dynamic and add the growth animations**

Replace the fixed `property int stage: 2` with:

```qml
    // 0 = square, 1 = summary pill, 2 = full panel. Driven by the hover
    // handlers below: the square opens the pill, the pill opens the panel.
    // Two deliberate steps, so the panel never springs open just because
    // the cursor crossed the corner on its way somewhere else.
    property int stage: 0
```

Add inside `Rectangle { id: shell }`, after `border.width`:

```qml
        Behavior on width {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 210; easing.type: Easing.OutCubic }
        }
        Behavior on radius {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }

        // Whole-widget hover: leaving by any edge collapses all the way
        // back to the square.
        HoverHandler {
            id: shellHover
            onHoveredChanged: if (!hovered) win.stage = 0
        }
```

- [ ] **Step 2: Add the two opening handlers**

Inside `Item { id: spineBox }`, as a child:

```qml
                HoverHandler {
                    onHoveredChanged: if (hovered && win.stage === 0) win.stage = 1
                }
```

Inside `Column { id: contentCol }`, as a child:

```qml
                HoverHandler {
                    onHoveredChanged: if (hovered && win.stage === 1) win.stage = 2
                }
```

The content column has zero width at stage 0, so it cannot be hovered until
the pill exists — which is what enforces the ordering without a guard on the
pointer's x coordinate.

- [ ] **Step 3: Stagger the detail fade so text does not reflow mid-growth**

The rows and footer currently appear the instant `stage` becomes 2, while the
height is still animating. Wrap their visibility in an opacity that trails the
growth. On the rows `Column` and the footer `Item`, replace
`visible: win.stage === 2` with:

```qml
                    visible: opacity > 0
                    opacity: win.stage === 2 ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                    }
```

- [ ] **Step 4: Verify the flake evaluates**

Run: `nix flake check`
Expected: exits 0.

- [ ] **Step 5: Re-render the preview**

Re-run the Task 2 Step 7 render loop so the preview picks up the new file.

- [ ] **Step 6: Test hover in a nested sway window**

Headless cannot do this. `docs/greeter.md`: *"A headless seat has no pointer
device. `swaymsg seat … cursor` returns success and does nothing, so hover and
click cannot be tested headless. Use the nested window."* This widget is
entirely hover-driven, so the nested window is mandatory, not a preference.

```bash
cd /tmp/status-preview
WLR_BACKENDS=wayland sway -c /dev/null &
sleep 2
WAYLAND_DISPLAY=wayland-1 quickshell -p /tmp/status-preview/ &
```

Then, with a real pointer in the nested window:
- Move onto the square → it grows right into the pill, showing the verdict
  and the count.
- Move right into the pill → it grows upward into the full panel.
- Move off any edge → it collapses straight back to the square.
- Move the pointer across the empty area above the square → the window below
  receives the input (nothing highlights, no click is swallowed). This is the
  `mask` working.
- Hover one row → its sparkline and latency swap for `cpu`/`ram`, and nothing
  else on the row shifts position.

- [ ] **Step 7: Confirm the collapse is not jumpy**

Move the pointer onto the square and off again several times quickly, faster
than the 190ms animation.

Expected: the widget retargets cleanly with no stuck intermediate width and no
flicker between stages. If it looks wrong, fix the state logic — do **not**
lengthen the durations.

- [ ] **Step 8: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/StatusPanel.qml
git commit -m "feat(status): add the three-stage hover interaction"
```

---

### Task 5: Real-hardware and cross-polarity validation

**Files:**
- No source changes expected. Any fix found here is a follow-up commit to the
  file that owns the defect.

**Interfaces:**
- Consumes: the finished component.
- Produces: nothing.

- [ ] **Step 1: Switch the home-manager profile**

The server side may not be deployed yet. That is fine and is itself a test
case: the widget must sit quietly in the `unknown` state rather than
misbehaving.

**Ask before running this** — the repo's working agreement is to confirm
before any `switch`.

```bash
nix run nixpkgs#home-manager -- switch --flake .#personal
systemctl --user restart quickshell-widgets
journalctl --user -u quickshell-widgets -n 40 --no-pager
```

Expected: no QML errors, no `ReferenceError`, no "Cannot assign to
non-existent property".

`font.features` (used for tabular figures on every number) requires Qt 6.7 or
newer. If the journal reports it as a non-existent property, the Qt in this
nixpkgs pin is older than assumed: drop the `font.features` lines and set
`font.family` on those `Text` elements to a monospace face instead. Tabular
alignment is the requirement; `font.features` is only the preferred means,
because it keeps the numbers in the UI sans.

If the log shows `Failed to create wl_display`, the systemd user environment
is stale — that is a known environment issue, not a QML defect. Re-import the
Wayland environment and restart the service.

- [ ] **Step 2: Verify the offline state on real hardware (Review Focus)**

With `oserv` unreachable (server side not yet deployed, or Tailscale down):

Expected: a dimmed grey square in the bottom-left. Hovering reads "No route
to oserv" with an em dash for the count. No red anywhere. Expanding shows
every row grey with em dashes and no latency.

- [ ] **Step 3: Verify against the real API once `oserv` is deployed**

```bash
curl -s http://status.tail.ogama.me/api/v1/endpoints/statuses | jq -r '.[].key'
```

Cross-check every key against the `labels` map in `StatusModel.qml`. Any key
the server reports that the map lacks renders with its raw Gatus name — which
is correct behaviour, but if the name is ugly, add the entry now. Any key in
the map that the server does not report is dead weight; remove it.

- [ ] **Step 4: Verify staleness detection (Review Focus)**

With the widget showing live green data, make the API hang rather than fail —
block the port so the TCP connection is accepted but never answered:

```bash
sudo iptables -I OUTPUT -p tcp --dport 80 -d "$(getent hosts status.tail.ogama.me | cut -d' ' -f1)" -j DROP
```

Expected: within roughly 35–40s the widget drops to the `unknown` state rather
than continuing to show stale green. Then remove the rule:

```bash
sudo iptables -D OUTPUT -p tcp --dport 80 -d "$(getent hosts status.tail.ogama.me | cut -d' ' -f1)" -j DROP
```

Expected: the widget recovers to live data on the next poll, within 10s.

- [ ] **Step 5: Verify a real degraded and a real down state**

Stop one service on `oserv` and confirm the widget follows within ~25s (15s
probe plus 10s poll):

Expected: that service's band and row go red, its name turns red, its latency
reads "no reply", the verdict reads "1 service down", and the count drops by
one. Restart the service and confirm it returns to teal.

- [ ] **Step 5b: Note on the degraded tier**

Every service on `oserv` currently answers in under 36ms against a 300ms
condition, so the amber state **cannot be provoked by normal load**. It is
covered by the fixture in Task 2 Step 12, which is the real test. To see it on
hardware, temporarily tighten one endpoint's condition server-side to
`[RESPONSE_TIME] < 5` and confirm that row goes amber, its name stays the
normal colour (not red), and the verdict reads "1 service slow" — then revert
it. Treat this as optional; do not leave the tightened condition deployed.

- [ ] **Step 6: Verify the light polarity**

Switch `stylix.polarity` to `"light"`, rebuild, and restart the widget.

Expected: the square is the darker teal `#1D8991` on the light ground and is
still clearly distinguishable from the red `#DA103F`. The surface is the light
Horizon ground at 70% and text remains legible. No hex from the dark palette
leaks through — the semantic colours come from `statusColors` in `default.nix`,
so a dark value appearing here means the polarity branch is not being
evaluated.

Restore the original polarity afterward.

- [ ] **Step 7: Verify the widget reserves no space and steals no focus**

Expected: sway's usable area is unchanged — tile a window and confirm it still
reaches the bottom-left corner behind the widget. Keyboard focus never lands
on the widget when cycling windows.

- [ ] **Step 8: Verify the other widgets are unaffected**

Expected: `Clock`, `Music`, `Calendar`, `Wallpaper`, `LaserBar`, and the lock
surface all behave exactly as before. The lock screen in particular shares
`qml-theme.nix`, so confirm it still renders with correct colours.

- [ ] **Step 9: Commit any fixes**

Stage only the files you actually changed. This working tree carries
unrelated in-progress work, so `git add -A` would sweep it into this branch.
Check `git status --short` first and stage explicit paths. The same applies to
every commit step in this plan.

```bash
git add modules/home-manager/display/sway/quickshell/components/<file>.qml
git commit -m "fix(status): <what the validation actually found>"
```

If nothing needed fixing, skip this step rather than making an empty commit.
