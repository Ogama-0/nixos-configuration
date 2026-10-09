# oserv status API — server-side design

**Date:** 2026-10-09
**Scope:** server side only (`host/serveur`, `modules/nixosconf`). The desktop
widget that consumes this API is a separate workstream; its contract is frozen
in section 3 and must not change without updating both sides.

## 1. Context

`oserv` (domain `ogama.me`, reachable over Tailscale as `*.tail.ogama.me`)
already runs an observability stack in `host/serveur/nixosconf/grafana.nix`:
Prometheus on `127.0.0.1:9001`, node-exporter on `9002` with the `systemd`
collector, process-exporter on `9256`, Loki on `3030`, Alloy, and Grafana on
`127.0.0.1:3000` behind Caddy at `grafana.tail.ogama.me`.

A Quickshell widget on the `personal` laptop needs to show live per-service
health in the corner of the desktop. Grafana is the wrong source for it: its
API requires a provisioned token and returns chart-shaped time series, so a
boolean "is Jellyfin answering" costs an authenticated range query.

This spec adds a purpose-built health API in two layers:

- **Reachability** — Gatus actively probes each service and exposes an
  unauthenticated JSON endpoint. This is the authoritative up/down signal.
  A systemd unit can be `active` while the service is wedged; a probe catches
  that, unit state does not.
- **Resources** — Prometheus's existing metrics, exposed read-only, supply
  per-service CPU/RAM and host load/memory/disk for the detail view.

Two layers rather than one because they answer different questions and have
different freshness needs. Reachability is the headline and must be fresh;
resource numbers are supporting detail and can lag.

## 2. What gets monitored

Eight services, matching what `host/serveur/configuration.nix` actually
imports today. Joplin and Crafty are commented out there and are out of scope
until they are re-enabled.

| Service | Probe target | Backing port |
|---|---|---|
| Jellyfin | `http://jellyfin.tail.ogama.me` | 8096 |
| Immich | `http://immich.tail.ogama.me` | 2283 |
| Immich ML | `http://127.0.0.1:3003/ping` | 3003 (verify, see below) |
| Samba | `tcp://127.0.0.1:445` | 445 |
| Caddy | `http://127.0.0.1:2019/metrics` | 2019 (admin API) |
| Grafana | `http://grafana.tail.ogama.me/api/health` | 3000 |
| Wakapi | `http://wakapi.tail.ogama.me` | 3033 |
| qBittorrent | `http://qbittorrent.tail.ogama.me` | 8080 |

**Probe through the public hostname, not localhost, wherever a vhost exists.**
The question the widget answers is "can I use this", and that whole path
includes DNS, Tailscale, Caddy, and the backend. The tradeoff is deliberate: if
Caddy dies, every row goes red at once — which is correct, and the Caddy row
tells you why. Immich ML and Samba have no vhost, so they are probed directly.

**Open item for the implementer:** confirm Immich ML's actual listen port and
health path on the running system before committing the config.
`services.immich.machine-learning` does not expose a port option in the module,
so read it off the live process (`ss -ltnp | grep immich` or the unit's
environment) rather than trusting 3003. If it has no usable HTTP health path,
fall back to a `tcp://` probe on its real port.

## 3. API contract (frozen — the widget depends on this)

### 3.1 Gatus

`GET http://status.tail.ogama.me/api/v1/endpoints/statuses` returns a JSON
array, one element per endpoint, unauthenticated. Verified against gatus
`config/endpoint/status.go` and `result.go`:

```json
[
  {
    "name": "Jellyfin",
    "group": "media",
    "key": "media_jellyfin",
    "results": [
      {
        "status": 200,
        "hostname": "jellyfin.tail.ogama.me",
        "duration": 42318000,
        "success": true,
        "timestamp": "2026-10-09T12:41:07.182Z",
        "conditionResults": [
          { "condition": "[STATUS] == 200", "success": true },
          { "condition": "[RESPONSE_TIME] < 300", "success": true }
        ]
      }
    ]
  }
]
```

Three properties the widget relies on:

- **`duration` is a Go `time.Duration`, serialised as nanoseconds.** Divide by
  1e6 for milliseconds. Do not change this by post-processing; the widget does
  the division.
- **`key` is `{group}_{name}`, lowercased and slugified.** It is the stable
  join key between a Gatus endpoint and its Prometheus metrics and its
  widget-side display label. **Renaming a group or an endpoint changes the key
  and silently breaks that join** — treat keys as an API surface.
- **`Uptime` is excluded from this response** (`json:"-"` on the struct). There
  is no uptime percentage here. The `results` array is a rolling recent
  history; the widget derives trend from it. Do not try to add an uptime field.

Every endpoint must declare **exactly these two conditions, in this order**:

```
[STATUS] == 200
[RESPONSE_TIME] < 300
```

This split is load-bearing. The widget reads `conditionResults` to distinguish
three states, and collapsing them to one condition destroys the middle tier:

- status condition failed → **down** (red)
- status passed, response-time failed → **degraded** (amber)
- both passed → **up**

For the `tcp://` Samba probe, use `[CONNECTED] == true` in place of the status
condition, keeping the response-time condition as the second element.

### 3.2 Prometheus

`GET http://metrics.tail.ogama.me/api/v1/query?query=<promql>` — standard
Prometheus instant-query response. The widget issues exactly these queries:

```promql
# per-service CPU, as a fraction of one core
rate(namedprocess_namegroup_cpu_seconds_total[1m])

# per-service resident memory, bytes
namedprocess_namegroup_memory_bytes{memtype="resident"}

# host load, 1 minute
node_load1

# host memory used, fraction
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# host root filesystem used, fraction
1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})
```

The `groupname` label on the `namedprocess_namegroup_*` series is what ties a
row to its service. **The process-exporter `name` values and the Gatus endpoint
names must be kept aligned** so the widget can join them; where they cannot be
(the existing matchers use names like `immich-server`), the widget maintains an
explicit map, so document any mismatch in a comment rather than renaming
matchers and breaking the existing Grafana dashboard.

## 4. Implementation

### 4.1 New module: `modules/nixosconf/status-page.nix`

Enable `services.gatus` (nixpkgs 26.05 ships 5.36.0; the module has been in
nixpkgs since 24.11 and takes a freeform `settings` attrset rendered to YAML,
so no hand-maintained config file).

Required settings:

- `web.address = "127.0.0.1"`, **`web.port = 8085`**. Not the Gatus default of
  8080 — `services.qbittorrent.webuiPort` defaults to 8080 and is already in
  use on this host. Using the default would collide.
- `storage.type = "sqlite"` with a path under the unit's state directory, so
  the `results` history survives a restart instead of starting empty. With the
  default in-memory storage, every rebuild blanks the widget's sparklines.
- `endpoints` — the eight entries from section 2, each with `interval = "15s"`,
  the two conditions from 3.1, and a `group` chosen so the resulting keys are
  stable and readable (`media`, `files`, `web`, `dev`).
- No `security` block. The API is intentionally unauthenticated; it is reached
  only over Tailscale (see section 5).

Probe interval is 15s. The widget polls every 10s, which means it sees each
result roughly once — polling faster buys nothing because the data has not
changed, and probing faster multiplies load on the probed services for no
visible gain.

Add the module to the `imports` list in `host/serveur/configuration.nix`,
grouped with the other service modules.

### 4.2 Caddy vhosts

Two new entries, following the `http://` scheme-prefix convention already used
for the tail hosts in this repo (plain HTTP, no ACME, since a wildcard cert
would need DNS-01 which is not configured — see the comment in
`modules/nixosconf/caddy.nix`):

```
http://status.tail.ogama.me   → reverse_proxy http://127.0.0.1:8085
http://metrics.tail.ogama.me  → Prometheus, path-restricted (below)
```

The Prometheus vhost **must not** be a bare `reverse_proxy` to `:9001`.
Prometheus's HTTP API is unauthenticated and would expose every metric on the
host, plus the targets, config, and flags endpoints. Restrict it to the single
read path the widget uses:

```
handle /api/v1/query* {
    reverse_proxy http://127.0.0.1:9001
}
handle {
    respond 404
}
```

This is still a read-only window onto all metric *data* for anyone on the
tailnet, which is an accepted tradeoff here. It does block config, flags,
targets, and the admin/TSDB endpoints.

Place the status vhost in the new `status-page.nix` module (keeping the service
and its vhost together, as `jellyfin.nix` and `wakapi.nix` already do) and the
metrics vhost in `grafana.nix` next to the existing Grafana vhost, since it
exposes the Prometheus that file configures.

### 4.3 Extend process-exporter

`grafana.nix`'s `exporters.process.settings.process_names` currently matches
jellyfin, immich-server, immich-machine-learning, samba-smbd, wakapi, and
qbittorrent. Caddy and Grafana are missing, so two of the eight widget rows
would show no CPU/RAM. Add:

```nix
{ name = "caddy";   comm = [ "caddy" ]; }
{ name = "grafana"; comm = [ "grafana" ]; }
```

Verify both `comm` values against the running processes before committing —
the existing comment block in that file documents why `comm`/`cmdline`
matching is used instead of cgroups, and Grafana's process name has varied
across packaging versions. Extend that comment to cover the two new entries.

### 4.4 Firewall

Nothing new. Caddy's 80/443 are already open in `caddy.nix`, Gatus and
Prometheus bind to loopback only, and Tailscale handles the rest. Do **not**
set `services.gatus.openFirewall`.

## 5. Security

- Gatus and Prometheus bind `127.0.0.1`. Only Caddy reaches them.
- Both new vhosts are `*.tail.ogama.me`, resolvable only on the tailnet, and
  are plain HTTP there like the existing tail hosts.
- Gatus's API is unauthenticated by design — it carries only service names and
  response times, no credentials, and the probes themselves need no secrets.
- The Prometheus vhost is path-restricted as described in 4.2. That restriction
  is the security control, so it must not be loosened to a bare proxy for
  convenience.

## 6. Verification

1. `nix flake check` — the flake evaluates.
2. `sudo nixos-rebuild switch --flake .#oserv` on the server. **Ask before
   running this**, per the repo's working agreement.
3. `systemctl status gatus` — active, no restart loop.
4. `curl -s http://127.0.0.1:8085/api/v1/endpoints/statuses | jq 'length'` → `8`.
5. `curl -s http://127.0.0.1:8085/api/v1/endpoints/statuses | jq '.[0].results[-1]'`
   — confirm `duration` is a large integer (nanoseconds, not milliseconds) and
   that `conditionResults` has two entries in the documented order.
6. `curl -s http://127.0.0.1:8085/api/v1/endpoints/statuses | jq -r '.[].key'`
   — record the exact keys; the widget side needs them verbatim.
7. Every endpoint reports `success: true`. Any that does not is either a real
   outage or a wrong probe target — resolve before calling this done.
8. `curl -s 'http://metrics.tail.ogama.me/api/v1/query?query=node_load1' | jq .status`
   → `"success"`, and `curl -s http://metrics.tail.ogama.me/api/v1/targets`
   → 404, proving the path restriction holds.
9. `curl -s 'http://metrics.tail.ogama.me/api/v1/query?query=namedprocess_namegroup_memory_bytes{memtype="resident"}' | jq -r '.data.result[].metric.groupname' | sort`
   — confirm all eight groups appear, including the two new ones.
10. Restart `gatus` and confirm the `results` history survived, proving sqlite
    storage is actually wired up.

Report the recorded keys from step 6 and any `groupname` mismatches from step 9
back to the widget workstream — those two lists are the join table.

## 7. Out of scope

- Gatus alerting and notification providers. The widget is the alert surface.
- A public status page. Tailnet-only is deliberate.
- Monitoring Joplin or Crafty, both currently commented out of
  `host/serveur/configuration.nix`.
- Any change to Loki, Alloy, or the existing Grafana dashboard.
- The Quickshell widget itself, including its QML, theming, and the
  `key` → display-label map.
