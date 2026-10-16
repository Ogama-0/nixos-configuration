# Laser Bar Modules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put workspace, clock and Wi-Fi modules on the laser bar, drawn as flared capsules clamped onto the beam, without changing the bar's held-key reveal or its battery collision.

**Architecture:** One reusable `BarShell.qml` draws the capsule-with-flares as a single closed `Shape`. `LaserBar.qml` gains a slot system that positions modules and wires their `RevealMask`. `BeamSide.qml` gains a span list so strands pinch around capsules, an amplitude-as-function-of-x hook for Wi-Fi, and a strand cache that pays for the lot. Data comes from `Quickshell.I3` and `Quickshell.Networking`, both signal-driven.

**Tech Stack:** Quickshell 0.3.x, Qt Quick `Shape`/`ShapePath` with `CurveRenderer`, home-manager `@token@` substitution via `modules/lib/qml-theme.nix`, headless sway + grim for verification.

**Spec:** `docs/superpowers/specs/2026-10-16-laser-bar-modules-design.md`

## Global Constraints

- The four items under the spec's **What must not change** are binding: momentary held-key reveal, two beams colliding at `batteryFraction`, `RevealMask` beam-sync on every module, clean retract. Any task that would break one is wrong.
- No `layer.effect`/`MultiEffect` on an item whose size changes. No `Canvas`. One `BeamSide` per side. No positioners for the workspace strip — explicit `x` arithmetic.
- Nothing runs while the bar is closed. Timers stay gated on `root.active || root.extent > 0`.
- Every new component file must be added to `treeFor` in `modules/home-manager/display/sway/quickshell/default.nix`. A file not in `treeFor` does not exist at runtime.
- Every new file must be `git add`ed before any `nix` command: flake evaluation ignores untracked files, so an un-added file makes checks pass against a tree without it.
- `nix flake check` does **not** force `xdg.configFile.*.text`. Validate generated QML with `nix eval --raw` on the attribute, for **both** `widgets-dark` and `widgets-light`, and never discard its stderr — a failed eval returns empty, which reads as "no leftover tokens".
- Animation durations are fixed by the spec: 170ms focus switch, 200ms workspace open/close, `Easing.OutCubic`. Do not lengthen one to hide a render artefact.

## Review Focus

Five conditions the spec implies that no feature step naturally exercises. Each has a test added to the task that owns the code.

- **No workspaces with windows** (fresh login): the workspace capsule must render nothing rather than a zero-width shell whose two flares meet in a black dart. → Task 6.
- **Named, non-numeric workspaces** (sway allows `workspace web`): `number` is `-1`. The cell must show something sane and must not print `-1`. → Task 6.
- **Wi-Fi absent or disconnected** (desktop, rfkill, no device): SSID empty and `signalStrength` undefined. Bars empty, rail flat, no `NaN` reaching a path. → Task 8.
- **Battery at 0% or 100%**: one rail has zero extent, so modules on that side are never revealed and the collision sits on a screen edge. Nothing may divide by a zero extent. → Task 2.
- **Light variant**: every new token resolves in `widgets-light` too, and the knockout ink on the focused cell stays legible against the light accent. → Task 3.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/laserbar-preview.sh` | Create: headless sway + quickshell + grim, renders any entry QML against a generated tree |
| `scripts/laserbar-probe.sh` | Create: assert one pixel's colour in a PNG, within a tolerance |
| `tests/laserbar/*.qml` | Create: fixture shells that instantiate one component for rendering |
| `.../components/BarShell.qml` | Create: the capsule-with-flares closed path |
| `.../components/WorkspaceModule.qml` | Create: the subdivided workspace capsule |
| `.../components/WorkspaceIcons.qml` | Create: drawn icon geometry, keyed by name |
| `.../components/WifiModule.qml` | Create: SSID + strength bars |
| `.../components/ClockModule.qml` | Modify: rebuilt on `BarShell` |
| `.../components/BeamSide.qml` | Modify: strand cache, pinch spans, amplitude function |
| `.../components/LaserBar.qml` | Modify: slot system, battery override, module blocks |
| `modules/lib/qml-theme.nix` | Modify: capsule tokens |
| `.../quickshell/default.nix` | Modify: register new components in `treeFor` |

All `.../components/` paths are under `modules/home-manager/display/sway/quickshell/`.

---

### Task 1: Verification harness

**Files:**
- Create: `scripts/laserbar-preview.sh`, `scripts/laserbar-probe.sh`
- Create: `tests/laserbar/README.md`
- Modify: `modules/home-manager/display/sway/quickshell/components/LaserBar.qml` (battery override)

**Interfaces:**
- Produces: `scripts/laserbar-preview.sh <entry.qml> <out.png> [battery-fraction]` — copies the generated `widgets-dark` tree to a temp dir, drops `<entry.qml>` in as `shell.qml`, runs nested headless sway at 1920x1080, calls `laserbar reveal` over IPC, writes `<out.png>`, exits non-zero if no PNG is produced.
- Produces: `scripts/laserbar-probe.sh <png> <x> <y> <w> <h> --near '#rrggbb' [tol=24] | --dominant r|g|b [margin=18]` — averages the region and asserts it, exit 1 printing the average on failure. A region, not a pixel: the beam's strands and its white core line make any single pixel a coin toss.
- Produces: `LASERBAR_FAKE_BATTERY` env var, read by `LaserBar.qml`, pinning `batteryFraction` so renders are deterministic.

- [ ] **Step 1: Write the failing check**

```bash
scripts/laserbar-preview.sh tests/laserbar/current-bar.qml /tmp/bar.png 0.5 \
  && scripts/laserbar-probe.sh /tmp/bar.png 200 16 80 14 --dominant g \
  && scripts/laserbar-probe.sh /tmp/bar.png 1620 16 80 14 --dominant r
```

`tests/laserbar/current-bar.qml` is a one-line fixture: `import "components"` and `Scope { LaserBar {} }`.

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — the scripts do not exist.

- [ ] **Step 3: Write both scripts and the battery override**

The preview script: `WLR_BACKENDS=headless`, `WLR_LIBINPUT_NO_DEVICES=1`, a private `XDG_RUNTIME_DIR`, sway with `output HEADLESS-1 resolution 1920x1080`, then `quickshell -p <tree>/shell.qml`, then `quickshell -p <tree>/shell.qml ipc call laserbar reveal`, then `grim -o HEADLESS-1`. Wait on the sway socket appearing rather than a fixed sleep. Probe with `magick <png> -format '%[pixel:p{X,Y}]' info:`. `magick` is not on this machine's PATH — fall back to `nix shell nixpkgs#imagemagick --command magick ...` when it is absent, so the harness runs on a bare checkout. `sway`, `grim`, `swaymsg` and `quickshell` are already present.

In `LaserBar.qml`, `batteryProc`'s handler takes `LASERBAR_FAKE_BATTERY` when it is set, otherwise the `/sys` reading as today.

- [ ] **Step 4: Run it to verify it passes**

Expected: both probes PASS. Green left of the 0.5 collision, red right of it.

- [ ] **Step 5: Commit**

```bash
git add scripts/laserbar-preview.sh scripts/laserbar-probe.sh tests/laserbar/ \
  modules/home-manager/display/sway/quickshell/components/LaserBar.qml
git commit -m "test(laser-bar): headless render harness and pixel probe"
```

---

### Task 2: BeamSide — strand cache, pinch spans, amplitude function

**Files:**
- Modify: `.../components/BeamSide.qml`
- Create: `tests/laserbar/beam-pinch.qml`

**Interfaces:**
- Consumes: Task 1's harness.
- Produces: on `BeamSide`, `property var pinchSpans: []` (array of `[x0, x1]` in panel coordinates, amplitude ramps to 0 inside each, over a 20px pad either side) and `property var amplitudeAt: null` (optional `function(px, strandIndex) -> real`; when null, today's constant is used).
- Produces: `property var strandCache` — the point arrays, computed once per `wavePhase` change and read by both `Repeater`s.

- [ ] **Step 1: Write the failing test**

Fixture `beam-pinch.qml` renders one `BeamSide` with `pinchSpans: [[800, 1000]]`. Probes:
- at `(900, 20)` and `(900, 48)`: background, not strand light — strands are flat inside the span.
- at `(700, 34)`: accent, beam still present.

And a zero-extent case (Review Focus): `LASERBAR_FAKE_BATTERY=0`, probe `(5, 34)` is background and the render completes — no `NaN` path, no division by a zero extent.

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL at `(900, 20)` — strands currently ignore `pinchSpans`.

- [ ] **Step 3: Implement**

`strandPoints(s, midY)` applies the pinch scale and `amplitudeAt` when set. Hoist the per-strand arrays into `strandCache`, recomputed on `wavePhase`/`extent`/`pinchSpans` change, and have the halo and core `Repeater`s both read `strandCache[index]` instead of each calling `strandPoints`.

- [ ] **Step 4: Run to verify it passes**

- [ ] **Step 5: Measure**

Record `quickshell` CPU with the bar held open before and after, 1920px output. Expected: not worse; the cache should make it better. Put the two numbers in the commit body.

- [ ] **Step 6: Commit**

```bash
git commit -m "perf(laser-bar): cache strand points, add pinch spans and amplitude hook"
```

---

### Task 3: BarShell component and theme tokens

**Files:**
- Create: `.../components/BarShell.qml`
- Create: `tests/laserbar/shell-only.qml`
- Modify: `modules/lib/qml-theme.nix`, `.../quickshell/default.nix`

**Interfaces:**
- Produces: `BarShell` with `required property real bodyWidth`, `required property real bodyHeight`, `property real radius: 9`, `property real flare: 21`, `property real outline: 4.6`, `default property alias content`. Its own `width` is `bodyWidth + 2 * flare` — the flares are inside the item, so `RevealMask` covers them with the body.
- Produces: `readonly property real bodyX` — where the body starts inside the item, i.e. `flare`.
- Produces tokens: `@capsuleFill@`, `@capsuleInk@`, `@capsuleKnockout@`, defaulted in `qml-theme.nix` so `greetd.nix` and `lockVariant` keep working without passing them.

- [ ] **Step 1: Write the failing test**

Fixture renders one `BarShell` with `bodyWidth: 120`, `bodyHeight: 34`, centred. Probes:
- `(centre, 34)` is `@capsuleFill@` — body is filled.
- `(bodyX - 10, 34)` is `@capsuleFill@` — **the flare is filled too**, not background.
- `(bodyX - 10, 24)` is background — above the flare is open.
- `(bodyX, 17)` is `@capsuleInk@` — outline on the top edge.

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `BarShell.qml` does not exist.

- [ ] **Step 3: Implement the closed path**

One `ShapePath`, `preferredRendererType: Shape.CurveRenderer`, filled and stroked once. Path geometry is given in the spec's *The shell* section — tip, cubic with the first control point on the wire and the second on the endpoint's vertical axis, corner arc, edge, mirrored out. All four arcs sweep the same way.

- [ ] **Step 4: Run to verify it passes**

- [ ] **Step 5: Validate both generated variants**

```bash
git add -A && for v in dark light; do
  nix eval --raw ".#homeConfigurations.personal.config.xdg.configFile.\"quickshell/widgets-$v/components/BarShell.qml\".text" | grep -c '@' 
done
```

Expected: exit 0 both times and a `0` count. A non-zero count is an unsubstituted token. (Review Focus: light variant.)

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(laser-bar): BarShell capsule with flared ends"
```

---

### Task 4: Clock on the new shell

**Files:**
- Modify: `.../components/ClockModule.qml`
- Create: `tests/laserbar/clock-only.qml`

**Interfaces:**
- Consumes: `BarShell` from Task 3.
- Produces: `ClockModule` keeping its existing `coverLeft` / `coverRight` / `panelWidth` / `active` properties unchanged, so `LaserBar.qml` needs no edit for it.

- [ ] **Step 1: Write the failing test**

Probe the capsule body fill at the clock's centre and `@capsuleInk@` on its outline, and assert the old parallelogram is gone: at the body's top-left corner, where the shear used to cut the plate away, the pixel is now fill rather than background.

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement**

128 × 34 `BarShell` containing `HH:mm` in Orbitron at 19px, `@capsuleKnockout@`. Keep the existing `Timer`. Delete the parallelogram geometry, the `shear`/`d1`/`d2` corner maths and the seconds sliver — the spec says the clock carries the time and nothing else.

- [ ] **Step 4: Run to verify it passes**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(laser-bar): rebuild the clock on BarShell"
```

---

### Task 5: Slot system

**Files:**
- Modify: `.../components/LaserBar.qml`
- Create: `tests/laserbar/slots.qml`

**Interfaces:**
- Produces: modules are declared with `slotSide` (`"left"`, `"centre"`, `"right"`) and `slotOrder` (int); `LaserBar.qml` positions them along `beamY` and injects `coverLeft`, `coverRight`, `panelWidth`, `active`. Left slots lay out rightward from a 24px margin, right slots leftward from a 24px margin, centre is centred. Spacing between adjacent slots on a side: 16px.
- The exact mechanism (attached property, a declared pair on each module, a positioning function) is the implementer's call provided adding a module stays one block with no positioning code of its own.

- [ ] **Step 1: Write the failing test**

Fixture declares three `ClockModule`s at left/centre/right. Probe each expected capsule centre for `@capsuleFill@`, and probe the 16px gap between two left-slot modules for beam, not fill.

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run to verify it passes**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(laser-bar): slot system for bar modules"
```

---

### Task 6: Workspace module, static

**Files:**
- Create: `.../components/WorkspaceModule.qml`, `.../components/WorkspaceIcons.qml`
- Create: `tests/laserbar/workspaces.qml`
- Modify: `.../components/LaserBar.qml`, `.../quickshell/default.nix`

**Interfaces:**
- Consumes: `BarShell`, the slot system, `BeamSide.pinchSpans`.
- Produces: `WorkspaceModule` exposing `readonly property var occupiedSpan: [x0, x1]` for `LaserBar.qml` to feed into `BeamSide.pinchSpans`.
- Produces: `WorkspaceIcons.iconFor(name)` returning a path-data list, keyed `"code"`, `"web"`, `"chat"`, `"music"`, `"term"`, `"plain"`.
- Data: `Quickshell.I3` — `workspaces`, `focusedWorkspace`. No `Process`, no polling.

Values from the spec: cell 27 wide, focused 37, `+6` when the workspace number is two digits, height 38, radius 9. Default mapping 1→code, 2→code, 3→web, 4→chat, 5→music, 10→term, everything else `plain`. Focused cell filled with the covering rail's colour, icon and number in `@capsuleKnockout@`; when the focused cell is first or last, its fill is clipped to the **shell path** so it runs into the flare.

- [ ] **Step 1: Write the failing test**

With a fixture feeding a stub model of workspaces 1, 2, 3, 5, 10 focused on 3:
- probe the focused cell's centre is the green rail colour, and an unfocused cell's centre is `@capsuleFill@`;
- probe a divider x at mid-height is `@capsuleInk@`;
- **focused-at-end**: focus 10, probe 8px into the right flare — it is the accent, not fill;
- **empty** (Review Focus): zero workspaces, probe where the capsule would be — background, and the render completes;
- **named workspace** (Review Focus): a workspace with `number == -1`, probe that the number row is not ink-coloured where `-1` would draw, and the cell still renders.

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement**

Explicit `x` arithmetic for the cells, not a `Row`. Each cell's content clipped to its own cell rect.

- [ ] **Step 4: Run to verify it passes**

- [ ] **Step 5: Validate both generated variants with `nix eval --raw` as in Task 3**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(laser-bar): workspace module"
```

---

### Task 7: Workspace animations

**Files:**
- Modify: `.../components/WorkspaceModule.qml`
- Create: `tests/laserbar/workspace-anim.qml`

**Interfaces:**
- Consumes: Task 6's cell layout.
- Produces: nothing new; cell `width` gains a `Behavior`, and the capsule is centred on a fixed point so growth opens it both ways.

- [ ] **Step 1: Write the failing test**

The fixture exposes `t` to drive the animation deterministically and renders at a pinned mid-animation width. Probes:
- the capsule's left tip has moved **left** between the settled and mid-grow renders — the strip opens both ways rather than only rightward;
- at a 2px cell width, the neighbouring cell's centre shows that cell's own content, not the new cell's icon bleeding over it (content clip).

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement**

`Behavior on width`, 170ms `OutCubic` for focus change, 200ms for a cell entering or leaving; a cell is destroyed when its width reaches 0.

- [ ] **Step 4: Run to verify it passes**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(laser-bar): animate workspace switch, open and close"
```

---

### Task 8: Wi-Fi module

**Files:**
- Create: `.../components/WifiModule.qml`
- Create: `tests/laserbar/wifi.qml`
- Modify: `.../components/LaserBar.qml`, `.../quickshell/default.nix`

**Interfaces:**
- Consumes: `BarShell`, the slot system, `BeamSide.amplitudeAt`.
- Data: `Quickshell.Networking` — `signalStrength`, SSID, `state`. No `Process`, no polling.
- `LaserBar.qml` sets the **right** `BeamSide`'s `amplitudeAt` to ramp from the signal level at the screen edge down to a calm baseline past this module. One `BeamSide`, not two.

- [ ] **Step 1: Write the failing test**

- 148 × 34 capsule, SSID left, four bars right; probe a filled bar is ink and an unfilled one is faint;
- probe the beam amplitude: with strength high, a pixel off-centreline between the screen edge and the module carries strand light; with strength low it does not;
- probe there is **no vertical seam** where a second rail would have started: scan the row at `y = 20` across the junction and assert no abrupt change — one rail, not two;
- **disconnected / no device** (Review Focus): `state` down and `signalStrength` undefined — no bar filled, the rail is flat, and the render completes with no `NaN` in a path.

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run to verify it passes**

- [ ] **Step 5: Validate both generated variants with `nix eval --raw` as in Task 3**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(laser-bar): wifi module with signal carried by the rail"
```

---

### Task 9: Whole-bar verification

**Files:**
- Modify: none expected.

- [ ] **Step 1: Render the real bar**

```bash
scripts/laserbar-preview.sh tests/laserbar/current-bar.qml /tmp/full.png 0.62
```

Check by eye against the design: workspaces left, clock centre, Wi-Fi right, collision at 62%, capsules clamped on the wire.

- [ ] **Step 2: Confirm the untouched behaviour**

Hold `Insert` on the real session: the bar reveals, the beams travel from both edges, they collide at the battery percentage with `CollisionEffects` firing, every module is revealed by the passing tip, and release retracts it to nothing with no module left painted.

- [ ] **Step 3: Confirm the cost**

`quickshell` CPU with the bar held open, against the number recorded in Task 2. Expected: no worse than the pre-change baseline.

- [ ] **Step 4: Flake check and switch**

```bash
git add -A && nix flake check
```

Then a real `home-manager switch --flake .#personal`, which is the user's call to run — ask first.

- [ ] **Step 5: Commit any fixes**
