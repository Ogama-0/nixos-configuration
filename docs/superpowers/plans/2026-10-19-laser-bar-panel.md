# Laser Bar Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A glass panel summoned from the laser bar's clock carrying toggles, clock/weather, an interactive calendar, metrics, disks, notifications and audio output.

**Architecture:** One `ControlPanel.qml` `PanelWindow` owns a three-state machine (`attached`/`detached`/`gone`) and an IPC surface; each zone is a separate component under `components/panel/`, and every zone that reads the system splits into a non-visual `*Model.qml` plus a renderer, the way `StatusModel.qml` backs `StatusPanel.qml`. Quickshell takes over the freedesktop notification bus and mako is removed.

**Tech Stack:** Quickshell/QML (Qt 6), Nix home-manager, khal/vdirsyncer, PipeWire/WirePlumber, NetworkManager, bluez, power-profiles-daemon, gammastep, Open-Meteo, geoclue.

**Spec:** `docs/superpowers/specs/2026-10-19-laser-bar-panel-design.md`

**Visual reference:** `docs/previews/laser-bar-panel.html` — approved for layout, colour, typography, icons and all four animation timings. Open it in a browser before building any zone.

## Global Constraints

- Every rule in `docs/adding-a-bar-widget.md` § "Rules that are not negotiable" applies. In particular: **no `Canvas`**; no `layer.effect` on anything that resizes; **a `Shape` only draws data it had at load** — build dynamic geometry by pushing `ShapePath`s from a `Repeater` as `BeamSide` does, or draw with `Rectangle`s; no `Row`/`RowLayout` for anything that animates, use explicit `x` arithmetic.
- **All dimensions in 1080p-equivalent pixels multiplied by `uiScale`.** Write `width: 940 * uiScale`.
- **Nothing runs while the panel is closed.** Every timer, poller and process gates on the panel's open state.
- **Colours come only from `modules/lib/palette.nix` base16 slots**, reaching QML as `@token@` substitutions through `modules/lib/qml-theme.nix`. No literal hexes in QML. The sole derived value is ink-on-accent: `base00` in dark, `base07` in light.
- **The panel's geometry never changes during attach, detach or re-attach.** Only the tail, the rails, the clock pill and the panel's shadow move.
- **Never `git add -A` in this repo** — the working tree always holds unrelated in-progress work. Add the exact paths each task touches. (`docs/adding-a-bar-widget.md` says `git add -A`; it is wrong for this tree. The real requirement is only that new files are *tracked* before `nix flake check`, since nix ignores untracked files.)
- **`nix flake check` does not force `xdg.configFile.*.text`.** It passes while generated QML throws. Every task that adds a QML file verifies the generated text directly for both variants, checking exit status and line count — a failed eval returns an empty string that greps clean for leftover `@tokens@` and looks exactly like a pass.

## Review Focus

Failure modes the spec implies but that no zone's happy path exercises. Each has a test pinned to the task that owns the code.

1. **khal absent or silent** (no calendars synced yet, vdirsyncer never ran) — the calendar pane must draw the month and an empty events list, not a blank zone. → Task 8.
2. **No network, or geoclue refuses a fix** — weather must show a dash and a reason, never hang the panel or leave the zone blank. → Task 7.
3. **`nvidia-smi` missing** (booted on amdgpu alone) — the GPU meter degrades to a dash; it must not spawn a failing process on every poll tick. → Task 9.
4. **A notification with no body, no app name, or a 4KB body, and a flood of 200** — the list must clamp and stay bounded rather than growing without limit. → Task 11.
5. **The panel is open when the lock screen appears** — it must dismiss, not draw over the lock. → Task 3.

## File Structure

**New, panel core**
- `modules/home-manager/display/sway/quickshell/components/ControlPanel.qml` — the `PanelWindow`, the state machine, the IPC handler, the layout grid.
- `.../components/PanelTail.qml` — the funnel, as a `Shape` with literal geometry.
- `.../components/PanelBeam.qml` — the fading hairline divider, horizontal or vertical.

**New, zones** (all under `.../components/panel/`)
- `ToggleModel.qml` / `ToggleGrid.qml` / `ToggleTile.qml` / `ToggleTip.qml`
- `WeatherModel.qml` / `ClockWeatherHead.qml`
- `CalendarPane.qml`
- `MetricsModel.qml` / `MetricsPane.qml`
- `DiskModel.qml` / `DiskPane.qml`
- `NotificationServer.qml` / `NotificationPane.qml`
- `AudioModel.qml` / `AudioPane.qml`
- `MobileStub.qml`

**New, shared**
- `.../components/CalendarModel.qml` — khal reading and month building, consumed by both the existing desktop `Calendar.qml` and the panel.
- `modules/home-manager/gammastep.nix`

**Modified**
- `.../quickshell/shell.qml` — add `ControlPanel {}`.
- `.../quickshell/default.nix` — register every new file in `treeFor`; add any new theme tokens.
- `modules/lib/qml-theme.nix` — new tokens.
- `modules/home-manager/display/sway/default.nix` — `Insert` → `Mod4`, add `Mod4+n`, drop the mako import.
- `.../components/ClockWidget.qml` — the pill becomes a click target.
- `.../components/Calendar.qml` — render `CalendarModel` instead of its own khal logic.

**Deleted**
- `modules/home-manager/display/sway/mako.nix`

**Fixtures** — one per task, in `tests/laserbar/`, on the standard `#FF2040A0` background.

---

### Task 1: Panel window, open and close over IPC

The panel as an empty glass sheet that can be opened and closed, with nothing in it. Everything else hangs off this.

**Files:**
- Create: `.../quickshell/components/ControlPanel.qml`
- Modify: `.../quickshell/shell.qml`, `.../quickshell/default.nix`
- Test: `tests/laserbar/panel-open.qml`, `tests/laserbar/panel-closed.qml`

**Interfaces:**
- Produces: `ControlPanel` with `property string panelState` (`"attached"`, `"detached"`, `"gone"`), `property bool isOpen` (`panelState !== "gone"`), `function summon()`, `function dismiss()`, `function detach()`, `function reattach()`, and an `IpcHandler` with `target: "panel"` exposing `open`, `dismiss`, `toggle`. Note the names: a `property bool open` would collide with a `function open()`, and `state` is taken by `Item`. Size `940 * uiScale` × `700 * uiScale`, centred horizontally, bottom-anchored above the bar.

- [ ] **Step 1: Write the failing fixtures**

`tests/laserbar/panel-open.qml` loads the shell and calls `summon()` on `Component.onCompleted`; `panel-closed.qml` is identical but never opens. The harness only drives `laserbar reveal`, so fixtures open the panel themselves.

- [ ] **Step 2: Render both and probe**

```sh
scripts/laserbar-preview.sh tests/laserbar/panel-open.qml   /tmp/open.png 0.62
scripts/laserbar-preview.sh tests/laserbar/panel-closed.qml /tmp/closed.png 0.62
scripts/laserbar-probe.sh /tmp/open.png /tmp/closed.png --diff
```
Expected: FAIL — `ControlPanel` does not exist, the renders are identical.

- [ ] **Step 3: Implement `ControlPanel.qml`**

A `PanelWindow` on `WlrLayer.Overlay`, `exclusionMode: ExclusionMode.Ignore`, keyboard focus `OnDemand` so Escape reaches it without stealing keys from the window underneath. Glass fill, 1px border and 26px corner radius from theme tokens, matching the preview. `visible: isOpen`.

- [ ] **Step 4: Register in `treeFor` and `shell.qml`, re-render, probe**

Expected: PASS — the two renders differ across the panel's rectangle.

- [ ] **Step 5: Verify the generated QML for both variants**

```sh
for v in dark light; do
  nix eval --raw ".#homeConfigurations.personal.config.xdg.configFile.\"quickshell/widgets-$v/components/ControlPanel.qml\".text" > /tmp/cp-$v.qml
  echo "$v exit=$? lines=$(wc -l < /tmp/cp-$v.qml)"; grep -c '@[a-zA-Z]*@' /tmp/cp-$v.qml
done
```
Expected: non-zero line counts, zero leftover `@tokens@`.

- [ ] **Step 6: Commit** — `git add` the three paths plus both fixtures.

---

### Task 2: The tail

**Files:**
- Create: `.../components/PanelTail.qml`
- Modify: `ControlPanel.qml`
- Test: `tests/laserbar/panel-tail.qml`

**Interfaces:**
- Produces: `PanelTail` with `required property real uiScale`, `property real openFraction` (0–1, drives the shoot/retract), `width: 300 * uiScale`, `height: 37 * uiScale`.

The spec's § "The tail" fixes the shape. Mouth 300 wide, neck at the clock pill's width, flanks stroked and **no line across the mouth**, top 3px overlapping the panel's bottom edge so that edge does not draw across the funnel, bottom running a few pixels behind the pill, and the beam's green glow.

- [ ] **Step 1: Write `tests/laserbar/panel-tail.qml`** — panel open, tail at `openFraction: 1`.
- [ ] **Step 2: Probe the neck and the mouth**

```sh
scripts/laserbar-preview.sh tests/laserbar/panel-tail.qml /tmp/tail.png 0.62
# glass in the neck, directly above the clock pill
scripts/laserbar-probe.sh /tmp/tail.png <neck-x> <neck-y> 20 6 --near '<glass>' 25
# and NO border line across the mouth: a band spanning the mouth must not be
# darker than its neighbours
scripts/laserbar-probe.sh /tmp/tail.png <mouth-x> <mouth-y> 200 3 --darker-than '<edge>'
```
Expected: FAIL.
- [ ] **Step 3: Implement `PanelTail.qml`** — `Shape` + `ShapePath`, `preferredRendererType: Shape.CurveRenderer`. **The path data must be a QML literal** (Global Constraints): animate `openFraction` with a mask or a clip, never by rewriting the path string.
- [ ] **Step 4: Re-render and probe.** Expected: PASS.
- [ ] **Step 5: Confirm the mouth probe fails without the fix** — temporarily stroke the mouth, re-render, see it go red, revert. A probe whose coordinates were worked out on paper is a guess until it has been seen red.
- [ ] **Step 6: Commit.**

---

### Task 3: The four transitions

**Files:** Modify `ControlPanel.qml`, `PanelTail.qml`
**Test:** `tests/laserbar/panel-detached.qml`, `tests/laserbar/panel-locked.qml`

**Interfaces:**
- Consumes: Task 1's state machine, Task 2's `openFraction`.
- Produces: transitions `summon` (gone→attached), `detach` (attached→detached), `reattach` (detached→attached), `dismissDocked` (attached→gone), `dismissFree` (detached→gone). Timings in the spec's table; easings in the preview.

The trap, learned the hard way in the preview: **resting-state bindings must stand down while a transition runs**, or they fight it — the re-attach broke because the detached state pinned the bar invisible while the rails animated back in behind it. Drive both from one state property rather than layering static bindings over animations.

- [ ] **Step 1: Write `panel-detached.qml`** — summon, then detach; assert the panel is still painted and the tail is gone.
- [ ] **Step 2: Probe.** Panel glass present, tail region equal to background. Expected: FAIL.
- [ ] **Step 3: Implement the five transitions.** Geometry frozen on the panel throughout (Global Constraints); only the tail, rails, pill and shadow move.
- [ ] **Step 4: Probe.** Expected: PASS.
- [ ] **Step 5: Round-trip test** — summon → detach → reattach → render; the result must match the plain summon render.

```sh
scripts/laserbar-probe.sh /tmp/roundtrip.png /tmp/summon.png --diff
```
Expected: no difference. This is the regression test for the bug above.
- [ ] **Step 6: Review Focus #5 — dismiss on lock.** `panel-locked.qml` opens the panel then raises the lock. Assert the panel is gone, not drawn over the lock.
- [ ] **Step 7: Commit.**

---

### Task 4: Summoning from the bar

**Files:** Modify `ClockWidget.qml`, `modules/home-manager/display/sway/default.nix`

- [ ] **Step 1: Correct the binding.** `default.nix:169-170` binds the bar to `Insert`; change both to `Mod4`. Confirm the user's own correction has not already landed before editing.
- [ ] **Step 2: Add `bindsym --no-repeat Mod4+n exec quickshell ipc -c widgets call panel toggle`.**
- [ ] **Step 3: Make the clock pill a click target** calling the same IPC, following `docs/adding-a-bar-widget.md` § "Making a widget clickable".
- [ ] **Step 4: Verify** — `nix flake check`, then confirm both bindings appear in the generated sway config:

```sh
nix eval --raw '.#homeConfigurations.personal.config.xdg.configFile."sway/config".text' | grep -n 'Mod4+n\|laserbar reveal'
```
- [ ] **Step 5: Commit.**

---

### Task 5: Layout skeleton

**Files:** Create `PanelBeam.qml`; modify `ControlPanel.qml`
**Test:** `tests/laserbar/panel-grid.qml`

**Interfaces:**
- Produces: `PanelBeam` with `property bool horizontal`, drawing a 1px line that fades to transparent at both ends. `ControlPanel` exposes six named zone slots: `toggleZone`, `metricZone`, `mobileZone`, `calendarZone`, `diskZone`, `notifyZone`, laid out per the spec's § Layout diagram with explicit `x`/`width` arithmetic (Global Constraints forbid positioners here).

- [ ] **Step 1: Write `panel-grid.qml`** — panel open with a distinctly coloured rectangle filling each of the six zones.
- [ ] **Step 2: Probe each zone's centre** for its colour, and probe the gutters for the beam. Expected: FAIL.
- [ ] **Step 3: Implement `PanelBeam.qml` and the zone layout.** No cards, no per-zone backgrounds — the dividers are the only separation (spec § Anti-goals).
- [ ] **Step 4: Probe.** Expected: PASS.
- [ ] **Step 5: Commit.**

---

### Task 6: Toggles

**Files:** Create `panel/ToggleModel.qml`, `ToggleTile.qml`, `ToggleGrid.qml`, `ToggleTip.qml`, `modules/home-manager/gammastep.nix`; modify `ControlPanel.qml`, `default.nix`
**Test:** `tests/laserbar/panel-toggles.qml`, `tests/laserbar/panel-toggle-tip.qml`

**Interfaces:**
- Produces: `ToggleModel` with `property var toggles` — a list of `{ key, icon, name, active, action }`, in the spec's table order: `dnd`, `profile`, `night`, `wifi`, `bt`, `dark`, `lock`. `ToggleTile` takes `icon`, `name`, `active`, `wide`, `action`.

Backends are in the spec's toggle table. Three details that are not obvious:

- `profile` has **three** states, not two — cycles power-saver → balanced → performance via `powerprofilesctl`, icon changes per state. `scripts/swaync/power-toggle.sh` already implements the cycle.
- `lock` is **not a toggle**: wide, spanning two columns, outlined rather than filled.
- **Night light and dark mode must not share the crescent.** Night light is a sun shedding warm wavy light; the crescent is dark mode's alone. They collided in an early draft and the row became unreadable.
- Active state must not be carried by text colour: `base0B` in light is `#94E1B0`, illegible as small text on cream.

`gammastep.nix` is a new module — gammastep is installed nowhere today; the old `scripts/swaync/night-shift-toggle.sh` drove `hyprsunset` under Hyprland.

- [ ] **Step 1: Write `panel-toggles.qml`** with a stubbed `ToggleModel` pinning `dnd`/`night`/`wifi`/`dark` active and `profile`/`bt` inactive.
- [ ] **Step 2: Probe** four tiles for accent fill, two for plate fill, and the lock tile for double width with no fill. Expected: FAIL.
- [ ] **Step 3: Implement the tile, the grid and the model.** Gate every backend read on `isOpen` (Global Constraints).
- [ ] **Step 4: Probe.** Expected: PASS.
- [ ] **Step 5: The tooltip must overhang the panel.** The panel clips to its rounded corners, so `ToggleTip` is **its own `PopupWindow`** — a tip drawn inside the panel can never cross its top edge. `panel-toggle-tip.qml` forces a tip on the top row; probe above the panel's top edge for ink.
- [ ] **Step 6: Write `gammastep.nix`** and import it from the sway profile.
- [ ] **Step 7: `nix flake check` plus the per-variant generated-text check from Task 1 for each new QML file.**
- [ ] **Step 8: Commit.**

---

### Task 7: Clock, date and weather

**Files:** Create `panel/WeatherModel.qml`, `panel/ClockWeatherHead.qml`; modify `ControlPanel.qml`, `default.nix`
**Test:** `tests/laserbar/panel-weather.qml`, `tests/laserbar/panel-weather-offline.qml`

**Interfaces:**
- Produces: `WeatherModel` with `property real tempC`, `property string condition`, `property string place`, `property bool ok`, `property string failure`. Open-Meteo, no API key; location from **geoclue**, not hardcoded.

- [ ] **Step 1: Write `panel-weather.qml`** with the model stubbed to 15°C / Clear / Paris.
- [ ] **Step 2: Probe** the temperature in Orbitron at the head's right, time large at its left. Expected: FAIL.
- [ ] **Step 3: Implement the head and the model.** Poll only while the panel is open.
- [ ] **Step 4: Probe.** Expected: PASS.
- [ ] **Step 5: Review Focus #2 — no network, or geoclue refuses.** `panel-weather-offline.qml` forces `ok: false`. The zone shows a dash and the reason; the panel must still render and must not hang. Probe the rest of the panel renders identically to Task 5's grid.
- [ ] **Step 6: Commit.**

---

### Task 8: The calendar

**Files:** Create `components/CalendarModel.qml`, `panel/CalendarPane.qml`; modify `components/Calendar.qml`, `ControlPanel.qml`, `default.nix`
**Test:** `tests/laserbar/panel-calendar.qml`, `tests/laserbar/panel-calendar-empty.qml`, `tests/laserbar/calendar-desktop.qml`

**Interfaces:**
- Produces: `CalendarModel` with `property date viewMonth`, `property date selected`, `property var monthCells`, `property var eventsForSelected`, `property var daysWithEvents`, `function shiftMonth(n)`, `function selectDay(date)`, `function goToday()`.
- Consumed by both `panel/CalendarPane.qml` and the existing desktop `components/Calendar.qml`.

**The desktop widget keeps running** (spec § Non-goals), so the panel cannot take it over. Lift the khal reading and month building out of `Calendar.qml` into `CalendarModel`, and render it from both. **Do not write a second khal parser.**

Behaviour fixed by the spec: month arrows with the name centred in a fixed-width box so the arrows do not shuffle; a **Today button that is always visible**, dimming to inert once you are on today; click any day to select; today stays marked when another day is selected; days with events get a dot; at most three events then "and N more". The events block is **pinned to the bottom of its zone with slack collecting above it**, or it jumps a row's height whenever you page into a six-row month.

- [ ] **Step 1: Write `panel-calendar.qml`** with `CalendarModel` stubbed: a six-row month, today mid-month, a different day selected, four events on the selected day.
- [ ] **Step 2: Probe** the selected day's accent fill, today's mark, an event dot, and the events block's top edge. Expected: FAIL.
- [ ] **Step 3: Implement `CalendarModel`** by moving the logic out of `Calendar.qml`.
- [ ] **Step 4: Implement `CalendarPane`.** Three events plus "and 1 more" for the four-event stub.
- [ ] **Step 5: Probe.** Expected: PASS.
- [ ] **Step 6: The five-row/six-row test.** Render a five-row month and a six-row month; probe the events block's top edge in both.

```sh
scripts/laserbar-probe.sh /tmp/cal5.png <events-x> <events-y> 200 2 --near '<ink>' 25
scripts/laserbar-probe.sh /tmp/cal6.png <events-x> <events-y> 200 2 --near '<ink>' 25
```
Expected: both PASS at the same y — the block does not move.
- [ ] **Step 7: Review Focus #1 — khal absent or silent.** `panel-calendar-empty.qml` stubs khal returning nothing. The month still draws; the events list reads its empty state. The zone must not be blank.
- [ ] **Step 8: The desktop widget still works.** `calendar-desktop.qml` renders the untouched `Calendar.qml` on the new model; probe it matches its pre-change render.
- [ ] **Step 9: Commit.**

---

### Task 9: Metrics

**Files:** Create `panel/MetricsModel.qml`, `panel/MetricsPane.qml`; modify `ControlPanel.qml`, `default.nix`
**Test:** `tests/laserbar/panel-metrics.qml`, `tests/laserbar/panel-metrics-nogpu.qml`

**Interfaces:**
- Produces: `MetricsModel` with `property int cpuPct`, `property int gpuPct` (`-1` when unavailable), `property int ramPct`, `property var cpuHistory`.

GPU source is the builder's call (spec § Open questions): `nvidia-smi` for the nvidia card, sysfs `gpu_busy_percent` for amdgpu. Reuse the existing `Sparkline.qml`.

- [ ] **Step 1: Write `panel-metrics.qml`** stubbed to 34/12/71 — the preview's values, with RAM in the warning band.
- [ ] **Step 2: Probe** each bar's fill width and RAM's warning colour. Expected: FAIL.
- [ ] **Step 3: Implement.** Poll only while open.
- [ ] **Step 4: Probe.** Expected: PASS.
- [ ] **Step 5: Review Focus #3 — no `nvidia-smi`.** `panel-metrics-nogpu.qml` stubs the binary missing. The GPU row shows a dash, and **the model must stop probing after the first failure rather than spawning a failing process every tick.** Assert on the log: exactly one spawn across a multi-tick render.
- [ ] **Step 6: Commit.**

---

### Task 10: Disks

**Files:** Create `panel/DiskModel.qml`, `panel/DiskPane.qml`; modify `ControlPanel.qml`, `default.nix`
**Test:** `tests/laserbar/panel-disks.qml`

**Interfaces:**
- Produces: `DiskModel` with `property var disks` — `{ mount, label, usedFraction, freeBytes }` — and `property string freeTotal`.

Vertical fill bars, one per mount, with a free-space total underneath. Vertical is the only shape that fits the narrow column.

- [ ] **Step 1: Write `panel-disks.qml`** stubbed to three mounts at 62% / 38% / 88%, the last in the warning band.
- [ ] **Step 2: Probe** each bar's fill height from the bottom. Expected: FAIL.
- [ ] **Step 3: Implement.** - [ ] **Step 4: Probe.** Expected: PASS. - [ ] **Step 5: Commit.**

---

### Task 11: Notifications

**Files:** Create `panel/NotificationServer.qml`, `panel/NotificationPane.qml`; modify `ControlPanel.qml`, `default.nix`, `modules/home-manager/display/sway/default.nix`; **delete** `modules/home-manager/display/sway/mako.nix`
**Test:** `tests/laserbar/panel-notify.qml`, `tests/laserbar/panel-notify-degenerate.qml`

**Interfaces:**
- Produces: `NotificationServer` with `property var notifications` (newest first, grouped by app), `property bool dnd`, `function dismiss(id)`, `function clearAll()`. Owns `org.freedesktop.Notifications`.

**No toasts this round** (spec § Non-goals). The server collects and pops nothing. Leave the popup surface unimplemented rather than half-built. The consequence is known and accepted: from the switch until toasts exist there are no popups at all and a notification is only visible by opening the panel.

Removing mako is part of this task — the two cannot both own the bus, so they must land in the same commit.

- [ ] **Step 1: Write `panel-notify.qml`** with three stubbed notifications across three apps.
- [ ] **Step 2: Probe** three rows, each with its accent edge. Expected: FAIL.
- [ ] **Step 3: Implement the server and the pane.** Collection continues while the panel is closed — this is the one exception to the gating rule, and it is why the server is a separate component from the pane.
- [ ] **Step 4: Probe.** Expected: PASS.
- [ ] **Step 5: Review Focus #4 — degenerate input.** `panel-notify-degenerate.qml` feeds: no body; no app name; a 4KB body; and 200 notifications. Assert the pane renders, each row stays within its zone, and the retained list is clamped to a documented maximum.
- [ ] **Step 6: Delete `mako.nix` and its import**, then `nix flake check`.
- [ ] **Step 7: Commit** — the server, the pane and the mako removal together.

---

### Task 12: Audio output, and the mobile stub

**Files:** Create `panel/AudioModel.qml`, `panel/AudioPane.qml`, `panel/MobileStub.qml`; modify `ControlPanel.qml`, `default.nix`
**Test:** `tests/laserbar/panel-audio.qml`

**Interfaces:**
- Produces: `AudioModel` with `property var sinks` — `{ id, name, isDefault }` — `property int volumePct`, `function setSink(id)`, `function setVolume(pct)`. PipeWire/WirePlumber.

Audio sits below a beam line at the bottom of the notification column. The mobile stub is a dimmed label — it should look deliberately unfinished (spec § Non-goals).

- [ ] **Step 1: Write `panel-audio.qml`** stubbed to three sinks, the second default, volume 58.
- [ ] **Step 2: Probe** the slider fill at 58% and the divider above the audio block. Expected: FAIL.
- [ ] **Step 3: Implement all three components.** - [ ] **Step 4: Probe.** Expected: PASS.
- [ ] **Step 5: Commit.**

---

### Task 13: Whole-panel render, performance, and the real switch

**Files:** Test only — `tests/laserbar/panel-full.qml`; modify `docs/adding-a-bar-widget.md`

- [ ] **Step 1: Write `panel-full.qml`** — every zone live, panel attached. Render in both variants and compare against `docs/previews/laser-bar-panel.html` side by side.
- [ ] **Step 2: CPU check.**

```sh
scripts/laserbar-cpu.sh tests/laserbar/panel-full.qml 20
```
Compare against the same command on `main`, back to back in one session — the absolute number drifts with what else the machine is doing.
- [ ] **Step 3: Closed-panel check.** Run the same with the panel never opened. **Nothing may poll.** Assert on the log: no weather fetch, no khal, no metrics spawn.
- [ ] **Step 4: Full verification.**

```sh
git add <every new path>      # never -A: nix ignores untracked files, and this
                              # tree always holds unrelated work in progress
nix flake check
```
Then the per-variant generated-text check for every new QML file.
- [ ] **Step 5: Document the panel** — extend `docs/adding-a-bar-widget.md` with a short "Adding a panel zone" section pointing at the model/renderer split and the gating rule.
- [ ] **Step 6: Commit.**
- [ ] **Step 7: The real switch is the user's to run.**

```sh
home-manager switch --flake .#personal && systemctl --user restart quickshell-widgets
```
Ask before running it. Note that this is the moment mako disappears and popups stop.
