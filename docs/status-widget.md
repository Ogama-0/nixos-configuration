# The oserv status widget

A bottom-left Quickshell surface on the `personal` profile showing live health
of the services on `oserv`. Three stages: an ambient rounded square whose
colour is the global verdict, growing on hover into a summary pill, then into
a per-service panel with latency, recent history, and CPU/RAM.

Server side is specced in
`docs/superpowers/specs/2026-10-09-oserv-status-api-design.md`; the build is
planned in `docs/superpowers/plans/2026-10-09-oserv-status-widget.md`.

## Where everything lives

- `modules/home-manager/display/sway/quickshell/components/StatusModel.qml` —
  non-visual. Owns both pollers, all JSON parsing, state derivation, and the
  key→label map. Exposes `services`, `online`, `verdictText`, `verdictCount`,
  `hostLoad`, `hostRam`, `hostDisk`.
- `.../components/StatusPanel.qml` — the `PanelWindow`, the health spine, the
  three stages, rows, footer. All sizes are in one block at the top of the
  file; scale the widget by editing that block alone.
- `.../components/Sparkline.qml` — per-row recent history.
- `.../quickshell/default.nix` — derives the polarity-correct semantic colours
  and the API URLs, registers the three files.
- `modules/lib/qml-theme.nix` — the `@token@` substitution. Shared with
  `modules/nixosconf/greetd.nix` and the lock surfaces.

Server side lives in the `oserv` checkout and is **not merged into this
branch**: the Gatus module (port 8085 — not Gatus's default 8080, which
`services.qbittorrent.webuiPort` already uses) and the path-restricted
Prometheus read vhost alongside the existing Grafana one in
`host/serveur/nixosconf/grafana.nix`. Merge it here before treating this repo
as the whole picture.

## The data path

Two layers, answering different questions:

- **Reachability** — Gatus actively probes each service every 15s and serves
  `GET http://status.tail.ogama.me/api/v1/endpoints/statuses`, unauthenticated.
  This is the authoritative up/down signal. A systemd unit can be `active`
  while the service is wedged; a probe catches that, unit state does not.
- **Resources** — one Prometheus instant query every 20s through
  `http://metrics.tail.ogama.me/api/v1/query`, path-restricted at Caddy.

The widget polls Gatus every 10s. Worst-case staleness is therefore ~25s.

Three service states plus one transport state: `up`, `degraded`, `down`, and
`unknown`. **`unknown` must never render as `down`** — unreachable is dimmed
grey, never red, or you learn to ignore red every time you leave the house.

## Adding and removing a service

Two edits, deliberately decoupled:

1. Server: add the endpoint to `services.gatus.settings.endpoints`. It must
   declare exactly two conditions — `[STATUS] == 200` (or `[CONNECTED] == true`
   for a `tcp://` probe) and `[RESPONSE_TIME] < 300`. That split is
   load-bearing: the widget reads `conditionResults` to tell `down` from
   `degraded`, and collapsing to one condition destroys the middle tier.
2. Widget: add a line to `serviceList` in `StatusModel.qml`.

`serviceList` is one line per service and is the only thing you edit on the
widget side. **Comment a line out to remove that service; uncomment or add one
to bring it in; move a line to reorder it.** Position in the list is the
display order and the spine's band order, so there is nothing to renumber, and
every line ends in a comma — including the last — so any single line can be
commented out on its own.

Confirm a key against the server before adding it; a typo silently hides the
row rather than erroring:

```
curl -s http://status.tail.<domain>/api/v1/endpoints/statuses | jq -r '.[].key'
```

**The list is authoritative.** A service the server probes but that is not
listed is not displayed — that is what makes commenting a line out an actual
delete rather than just un-labelling it. The cost is the mirror image: a
service added server-side stays invisible until it is added here too. If
*nothing* in the list matches what the server reports, the widget keeps the
configured rows on screen as `unknown` and the verdict reads "No matching
services", rather than blanking to an empty square that would look identical
to the widget not running.

`promGroup` is the process-exporter `groupname` that gives a row its CPU/RAM.
It cannot be derived from the key — several differ (`media_immich` →
`immich-server`, `files_samba` → `samba-smbd`) — and those matcher names are
load-bearing for the existing Grafana dashboard, so do not rename them to
match. Omit it for a service with no process matcher; that row simply shows no
CPU/RAM.

## The constraints that bite

**Layer choice.** The widget is on `WlrLayer.Bottom`. `Top` puts it over
application windows, which is wrong for an ambient widget. `Background` is also
wrong: `Wallpaper.qml` already occupies that layer and z-order between two
Background surfaces is creation-order dependent, so the widget can end up
behind the wallpaper and disappear. The cost of `Bottom` is that the square is
hidden whenever a window covers the bottom-left corner.

**The widget must render something before any fetch returns.** The idle
square's fill *is* the band list, so an empty list draws nothing at all — and
`goOffline()` maps over the existing rows, so an empty list never recovers.
`StatusModel` seeds `services` from `serviceList` in `Component.onCompleted`
for exactly this reason. Remove that and the widget becomes invisible whenever
`oserv` is unreachable at login.

**Do not use `Row`/`Column` for the rows or the spine.** Positioners size
themselves from their children during a polish pass. A `Repeater` whose
JS-array model is reassigned — which happens on every poll here — can rebuild
its delegates without that pass re-running, leaving a `Column` reporting its
padding as its full height and every child stacked at `y=0`. It is intermittent
across launches and stable within one, so a single verification run will
happily pass. Layout is explicit `y` arithmetic so band *n* lands on row *n* by
construction. If you touch it, verify by sampling repeatedly, not once.

**The spine spans the rows block, not the whole panel.** `bandTop` is
`headerH + rowsPad` and the bands are inset symmetrically rather than
separated by a gap — a gap between equal-height bands shifts every band's
centre off its row's centre, which is the one thing the spine has to get right.

## Gotchas already paid for

- Gatus `duration` is a Go `time.Duration`: **nanoseconds**. Divide by `1e6`.
- `Uptime` is excluded from the statuses response (`json:"-"`). There is no
  uptime percentage; derive trend from the `results` array.
- The API returns its array **sorted by key**, not in server config order.
  Never index into it positionally; band order comes from each entry's
  position in `serviceList`.
- Gatus keeps 50 results per endpoint. Drawn across the sparkline that is well
  under a pixel per point, and adjacent failure ticks merge so one outage reads
  as several. `Sparkline.maxPoints` draws the most recent slice.
- Sparkline scale is per-row and adaptive. Latencies here run 0.1ms (Samba, a
  TCP connect) to 35ms (Grafana), so any fixed ceiling able to show a 400ms
  degradation flattens every healthy row onto the baseline. The floor stops
  sub-millisecond jitter from autoscaling into drama; failed probes are
  excluded from the peak so a timeout cannot crush the real measurements.
- **PromQL `or` matches on label signature excluding `__name__`.** Two computed
  series that reduce to the same remaining labels collide and the right-hand
  one is dropped silently — `node_load1` and a bare host-memory ratio are both
  `{instance, job}`, and the memory value vanished with status `success` and no
  error. Every series in the combined query carries an explicit `slot` label
  and the parser reads that.
- process-exporter splits `cpu_seconds_total` by `mode` (user/system), so a
  bare `rate()` yields two series per service and a naive parser keeps one.
  Sum by `groupname`.
- The `[1m]` rate window needs two samples: the process job is scraped every
  15s server-side specifically so this works. The host's global
  `scrape_interval` is 1m.
- A Prometheus error arrives as **HTTP 200 with valid JSON and
  `status: "error"`**, so `curl` exits 0 and `Process.onExited` never sees it.
  All three failure exits route through `clearMetrics()`; otherwise stale
  CPU/RAM sit on screen looking live.
- `font.pixelSize` is int-typed. A literal `11.5` fails the component at load
  with "Invalid property assignment: int expected".
- `font.features: ({ "tnum": 1 })` needs Qt 6.7+. It works on the current pin;
  the fallback is a monospace family on those `Text` items.
- `qml-theme.nix` pairs its two lists positionally. A token added to one and
  not the other at the same index silently substitutes the wrong value. Count
  both after editing. Every new argument needs a default — `greetd.nix` and the
  `lockVariant` helper call the same function.
- From the **personal** profile the server domain is `cfg.server.server.domain`,
  not `cfg.server.domain`. `host/profiles.nix` builds `base // (extra base)`,
  and `cfg-perso`'s extra sets `server = cfg-server`, replacing base's `server`
  attrset rather than merging into it. Every other consumer in the repo is
  server-only, where `cfg` is already `cfg-server`.

## Colour

The two palettes disagree about where each hue lives, so no single base16 slot
means "up" in both: the dark palette (now the terminal palette, not Horizon)
puts cyan at `base0C`, while Horizon light puts teal at `base0E` and a
red-orange at `base0C`. The semantic colours are therefore chosen per variant
by `statusColorsFor` in `default.nix`, which the two generated trees call with
`"dark"` and `"light"` — the same way `laserColor` is selected per variant.

Contrast is measured against each theme's *composited* panel ground, not the
raw base16 value. Bands are UI components and need 3:1; the muted column is
13px text and needs 4.5:1. Horizon light's `base04` only reaches 2.5:1 and its
`base09` 2.4:1, which is why both are overridden for the light polarity.

`@panelBg@` is more opaque than `@cardBg@` (90% vs 70%). The clock and calendar
render 26–64px type over wallpaper only; this panel's muted column is 13px, and
wallpaper brightness is user-switchable via the picker, so the alpha is chosen
for the worst case rather than the current image.

## Previewing without a switch

Same approach as `docs/greeter.md`: render the QML by calling the **real**
`modules/lib/qml-theme.nix` via `nix eval`, passing the working-tree file, so
the preview is exactly what a rebuild installs. Point `statusApiUrl` at a local
fixture (`python3 -m http.server` over a directory containing
`api/v1/endpoints/statuses`) to exercise `down`/`degraded`/`unknown`, which
cannot be provoked against the live server while everything is up.

Harness notes beyond the greeter's:

- A headless seat has no pointer, so the hover stages cannot be driven there.
  The stage machine can be walked by assigning `win.stage` directly.
- `pkill -f <pattern>` matches the invoking shell's own command line. Use a
  character class (`status-previe[w]`) or kill by PID, or you kill the harness.
- Leftover preview instances keep drawing. A stale one from an earlier edit
  will sit on top of the new one and produce screenshots of code you already
  changed; confirm the corner is empty before trusting a capture.
- To photograph it over existing windows, lift the *preview copy* to
  `WlrLayer.Top`. Never the source.

## Validating a change

```
nix flake check
nix eval --raw '.#homeConfigurations.personal.config.xdg.configFile."quickshell/widgets/components/StatusPanel.qml".text' | grep -oE '@[a-zA-Z]+@'
```

`nix flake check` does **not** force `xdg.configFile` text, so it passes green
while a generated file throws. The `nix eval` above is what actually validates
it — and never redirect its stderr to `/dev/null`: a failed eval returns an
empty string, which then reads as "no leftover tokens" and looks like a pass.

Then switch and check the journal:

```
nix run nixpkgs#home-manager -- switch --flake .#personal
systemctl --user restart quickshell-widgets
journalctl --user -u quickshell-widgets -n 40 --no-pager
```

The `playerctld`/`MediaPlayer2` dbus warnings are pre-existing and unrelated.
