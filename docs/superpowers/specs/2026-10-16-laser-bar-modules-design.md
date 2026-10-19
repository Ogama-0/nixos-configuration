# Laser bar modules: workspaces, clock, Wi-Fi

Design document. Dated 2026-10-16.

## Intent

`modules/home-manager/display/sway/quickshell/components/LaserBar.qml` currently
carries exactly one module, the clock. This design adds two more (workspaces,
Wi-Fi), restyles the clock to match them, and replaces the ad-hoc placement of
modules with a slot system, so that adding a fourth or fifth module stays a
single block in `LaserBar.qml` the way `ClockModule` is today.

The visual language is new but derived from what is already there: a capsule
with a heavy black outline, flared at both ends so the beam opens into it and
becomes its border. It replaces the sheared parallelogram of the present
`ClockModule.qml`.

### Why now

The bar is held-open on a key (`Insert` at the time of writing; **superseded
2026-10-19** — it is the modifier now, tracked by sway itself through a
`bar { mode hide; modifier }` block and its `bar_state_update` event, because
sway stops firing a modifier's `--release` binding once it has been used as a
modifier).
Today it costs a keypress and shows the time, which is not worth the keypress.
Workspace state and Wi-Fi are the two things worth the gesture.

## What must not change

This is the hard constraint on the whole design. The bar's existing behaviour is
the product, not scaffolding around it:

- **Momentary reveal.** The key held reveals the bar and releasing it hides
  the bar. (`Insert` when this was written; the modifier since 2026-10-19 —
  see *Why now*.) The bar is not persistent and must not become
  persistent. `exclusionMode: ExclusionMode.Ignore` and `mask: Region {}` stay:
  the bar never reserves space and never takes the pointer.
- **Two beams, meeting on the battery.** The left beam travels
  `batteryFraction * width` from the left edge, the right beam travels
  `(1 - batteryFraction) * width` from the right. They collide at the battery
  percentage, and `CollisionEffects.qml` fires there. Green on the left, red on
  the right. This is the bar's whole reason for existing and no module may
  obscure, replace, or reinterpret it.
- **Beam-synced reveal.** Every module is revealed by `RevealMask` as the beam
  tip sweeps past it, and covered again on retract. A module must never simply
  appear. New modules get `coverLeft` / `coverRight` / `panelWidth` exactly as
  `ClockModule` does today.
- **The retract path.** Releasing the key must return the bar to nothing, with
  no module left painted and no animation still running. The existing
  `Behavior on leftExtent` / `rightExtent` (90ms, OutCubic) governs it.

Anything in the sections below that would conflict with the four points above
loses.

## Goals

- Workspaces, clock and Wi-Fi legible at a glance on a 70px-tall bar, over an
  arbitrary user-switchable wallpaper.
- Workspaces answer "which workspaces have windows, and where am I" — the
  swaybar question, not a fixed ten-slot grid.
- Adding a module later is one block in `LaserBar.qml`.
- No measurable increase in the bar's cost while open, and no increase at all
  while closed.

## Non-goals

- Click-to-switch workspaces. The bar has `mask: Region {}` and takes no
  pointer input; keep it that way.
- Showing workspaces with no windows.
- Multi-monitor per-output workspace filtering. One bar instance per screen
  already exists via `Variants`; the workspace module may show all workspaces
  for now.
- Wi-Fi interaction of any kind (connect, scan, pick network).

## Anti-goals

Things that would make this a failure even if it technically worked:

- The bar becoming slow enough to notice on keypress. It is a momentary
  gesture; a hitch on reveal destroys it.
- Any module that reads as a floating box sitting on top of the beam rather
  than something the beam runs into.
- Losing the collision moment, or making the battery meeting point harder to
  find than it is today.

## The shell

Every module, present and future, is drawn as one closed path: left tip, flare,
corner arc, top edge, corner arc, flare, right tip, and back along the bottom.
Filled once and stroked once, as a single `Shape`/`ShapePath`.

```
     ╱‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾╲
◄───(                 )───►     one path, fill + stroke
     ╲_______________╱
```

Geometry, with `Y` the beam centreline (34), `FLARE = 21`, corner radius `r`:

- Left tip at `(x - FLARE, Y)`, right tip at `(x + w + FLARE, Y)`.
- From the tip, a cubic whose first control point is `(tip ± FLARE*0.62, Y)` —
  so the curve leaves the tip horizontally, along the wire — and whose second
  control point is `(x, Y - (Y - (y+r))*0.45)`, on the endpoint's own vertical
  axis, so it arrives at `(x, y+r)` vertically, on the corner arc's tangent.
- Then `A r r 0 0 1` into the corner, the straight edge, the far corner, and
  the mirrored flare out to the other tip. All four arcs sweep 1.

Two details that were got wrong during design and must not be reintroduced:

- The flare is **part of the filled shape**. Filling only the body and stroking
  the flares separately leaves a bare vertical edge between the two flare
  curves where the fill stops. It is immediately visible.
- The flare must meet the corner **on its tangent**. Landing it inside the
  rounded corner leaves a step in the outline.

Fill is a near-opaque off-white; outline is near-black at ~4.6px. Both come
from new `@token@` substitutions in `modules/lib/qml-theme.nix` (see *Theming*).

The white beam core is drawn **behind** the capsules and stops at the flare
tips, fading to nothing over its last ~14px. It must not cross a capsule: a
3px bright line through a 32px capsule cuts the icon and the digits in half.
The wave strands pinch to zero amplitude as they enter a capsule's span and
swell back out past it, which is what makes the capsule read as clamped onto
the wire.

## Slot system

`LaserBar.qml` gains a slot concept: each module declares a side
(`left` / `centre` / `right`) and an order. The panel positions them along the
beam centreline and passes each one `coverLeft`, `coverRight` and `panelWidth`
for its `RevealMask`, so a new module needs no positioning code of its own.

The existing "add or remove a module by adding/removing one block here" comment
in `LaserBar.qml` stays true.

A module's item width must include **both flares**, not just the capsule body.
`RevealMask` clips on an x range relative to the panel; if the item is sized to
the body alone, the flares fall outside the mask and are revealed on a
different schedule from the thing they are attached to.

Width budget, so the left slot cannot run into the centre one: ten cells at 27
plus one focused at 37 plus two flares is about 320px. On the narrowest output
this profile runs on, half the width minus the clock's half (64) leaves well
over 500px. No collision rule is needed; if a future module makes one possible,
the centre slot wins and the left slot is what gives.

## Module: workspaces

One capsule containing one cell per workspace **that has windows**, in order.
Cell content is the app icon above, the workspace number below.

- Cell width 27, focused cell 37, plus 6 more for two-digit numbers (`10`
  touches the dividers otherwise). Height 38, corner radius 9.
- Cells are divided by heavy vertical rules drawn inside the outline.
- The focused cell is filled with the accent colour, icon and number knocking
  out dark. When the focused cell is **first or last**, its fill runs out into
  the adjacent flare and tapers to the point — clip the fill to the shell path,
  not to the capsule body.
- Accent colour is the colour of the rail covering that capsule (green left of
  the collision, red right of it), so it drifts with the battery.

Icons are drawn geometry, not font glyphs. The intended mapping is workspace 1
and 2 code, 3 browser, 4 chat, 5 music, 6–9 generic, 10 remote/terminal — but
see *Open to the builder*.

### Animation

Both of these are the same mechanism: a `Behavior on width` on the cell, with
the capsule **centred on a fixed point** so that growth opens it out to both
sides and the flares ride outward.

- **Focus switch**: the newly focused cell grows 27 → 37, the old one shrinks
  back. 170ms, `Easing.OutCubic`.
- **Workspace opened**: a new cell grows from width 0. 200ms, `OutCubic`,
  deliberately a touch weightier than a switch. **Closed** runs the same thing
  backwards and the cell is destroyed once it reaches 0.

Each cell's content must be clipped to its own cell bounds. A cell growing from
zero has a full-size icon and number from the first frame, and without the clip
they spill over the neighbouring cells.

Durations are deliberately short. Do not lengthen them to smooth out a render
artefact — fix the artefact.

## Module: clock

The same shell, 128 × 34, containing `HH:mm` in Orbitron at 19px. Nothing else:
no seconds bar, no date line, no progress sliver.

## Module: Wi-Fi

The same shell, 148 × 34: SSID on the left, four rising bars on the right
filled to the measured strength.

**Superseded 2026-10-17: dropped.** The owner did not want it - driving one
rail's amplitude from the signal made the two rails visibly different from
each other. Both rails now share one wave equation and the strength is shown
only by the bars in the capsule. The rest of this section is kept as the
record of what was built and why it went.

The signal is also carried by the beam itself. The **right rail's amplitude
ramps** from the signal level at the screen edge down to a calm baseline past
the Wi-Fi capsule. This must be done as an amplitude that varies with `x`
**inside the single existing right-hand `BeamSide`** — not by instantiating a
second `BeamSide` for the segment. Two instances produce a visible vertical
seam where they meet and, worse, a second blurred glow layer (see
*Performance*).

Disconnected flattens that stretch of beam and empties the bars.

## Data sources

Both are first-class in the pinned Quickshell (0.3.x, `Quickshell.I3` and
`Quickshell.Networking` are present in the built QML module tree). Neither
needs a subprocess or a poll loop:

- **Workspaces**: `Quickshell.I3` — sway speaks the i3 IPC. `workspaces`,
  `focusedWorkspace`, `event`. Socket-driven.
- **Wi-Fi**: `Quickshell.Networking` — `signalStrength`, SSID, `state`, over
  NetworkManager's DBus signals.

Do not add a `Process` + `Timer` for either. The existing `batteryProc` 30s
poll in `LaserBar.qml` is not a pattern to copy here; it predates these
modules.

## Performance

This matters more than anywhere else in the repo, because the bar is a
**momentary overlay bound to a held key**. Every cost is paid at the moment the
user presses the key and expects an instant response. The comments in
`BeamSide.qml` are a record of this going wrong twice already; read them before
touching anything in that file.

### The existing baseline

While open, `BeamSide.qml` recomputes its strand polylines on a 33ms timer. At
5 strands over a 1920px extent at a 3px step, that is roughly 640 points per
call. **`strandPoints(index, …)` is called twice per strand per frame** — once
by the halo `Repeater` and once by the core `Repeater` — so it runs 10 times
per side per frame, computing each array twice.

**Cache it.** Compute the strand point arrays once per phase tick into a
property and have both `Repeater`s read that property. This roughly halves the
existing per-frame strand cost and on its own more than pays for everything
this design adds.

### Hard rules

1. **No `layer.effect` / `MultiEffect` whose item resizes.** The ambient edge
   glow in `BeamSide.qml` is a fixed 160×44 rectangle specifically so its
   blurred texture is rendered once and then only alpha-composited. A previous
   version tracked `root.extent` and forced a GPU texture reallocation plus a
   full reblur on every frame of every reveal and retract; that is what made
   the bar laggy, and the bar is toggled constantly. Any "glow" this design
   calls for is a wide faint stroke under a crisp one — the double-stroke trick
   already used for the strands — never a blur.
2. **One `BeamSide` per side.** See the Wi-Fi module above.
3. **No `Canvas`.** Qt rasterises it on the CPU and re-uploads a texture every
   repaint; it was measured at 110% CPU here versus 7% idle. Everything is
   `Shape` + `ShapePath` with `preferredRendererType: Shape.CurveRenderer`.
4. **No positioners for the workspace strip.** Use explicit `x` arithmetic.
   `StatusPanel.qml` documents a case where a `Repeater` over a reassigned JS
   array model rebuilt its delegates without the polish pass re-running, leaving
   a `Column` reporting its padding as its full height and every child stacked
   at `y: 0`. The workspace list is rebuilt on every sway event; do not risk it.
5. **Nothing runs while the bar is closed.** The strand timer is already gated
   on `root.active || root.extent > 0`. The workspace and Wi-Fi models may stay
   subscribed (they are signal-driven and idle), but no timer, animation or
   geometry rebuild may run when the bar is hidden.

### Costs this design adds, and why they are acceptable

- **Strand pinching around capsules**: one span check per generated point,
  against a handful of spans. Noise next to the 640-point loop it sits inside.
  The span list changes only when a workspace opens or closes.
- **Capsule geometry**: static `ShapePath`s. `CurveRenderer` re-triangulates
  only when the geometry actually changes — which during a switch or
  open/close animation is every frame for the duration, for one small path.
  That is ~200ms of work per workspace event.
- **Core drawn behind capsules in segments**: the core polyline already exists;
  this splits it into 2–4 shorter ones. Fewer total points, not more.
- **Rail tint, focus accent**: property bindings on `meetX` and
  `focusedWorkspace`. Free.

### Verifying it

Before and after, with the bar held open on a 1920px output, compare CPU for
the quickshell process. The prior measurement in the tree is 7% idle versus
110% for the Canvas implementation; the current Shape implementation should be
the baseline to beat, and this change should not move it.

## Theming

New `@token@` entries in `modules/lib/qml-theme.nix` for the capsule fill,
capsule outline and knockout ink, with light and dark values, following the
existing pattern. Default them so `modules/nixosconf/greetd.nix` and the
`lockVariant` helper, which render none of these components, keep working
without passing them — the file already documents why that matters.

Every new component file must be registered in `treeFor` in
`modules/home-manager/display/sway/quickshell/default.nix`, for both variants.
A component added to the directory but not to `treeFor` will not exist at
runtime.

## Open to the builder

Settled as my call, flag if you disagree:

- **Icon set and mapping.** Drawn geometry, one path set per icon, and a
  default-by-workspace-number mapping matching the list above. A per-workspace
  override table in the QML is fine but is not required for a first cut.
- **What icon an unmapped workspace gets.** A generic square.
- **Urgent workspaces.** The accent flips red. If sway's urgent flag is awkward
  to reach from `Quickshell.I3`, drop it rather than polling for it.
- **Where the three modules sit along the beam.** Workspaces left, clock
  centre, Wi-Fi right is the obvious reading of the slot system and the layout
  the mockups used.
- **The exact shape of the slot API** — an attached property, a declared
  `side` / `order` pair on each module, or a positioning function in
  `LaserBar.qml`. Any of them is fine as long as adding a module stays one
  block and the module needs no positioning code of its own.

Needs the author's answer before it is built:

- **Nothing blocking.** Everything above is either settled or safely
  deferrable.

## Prior art in this tree

- `modules/home-manager/display/sway/quickshell/components/BeamSide.qml` — the
  beam, and the performance history.
- `.../ClockModule.qml` — the module being replaced; its `RevealMask` wiring is
  the template.
- `.../GlassPill.qml` — the other module template. It is not used by this
  design and may be left alone.
- `.../StatusPanel.qml` — explicit-`x`-arithmetic layout, and why.
