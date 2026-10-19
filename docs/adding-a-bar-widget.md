# Adding a widget to the laser bar

How to put something new on the bar — a DND toggle, a battery readout, a media
button. Read this before writing the QML; several of the constraints below are
non-obvious and two of them fail *silently*.

All paths are relative to
`modules/home-manager/display/sway/quickshell/components/` unless stated.

## What the bar is

The bar is a momentary overlay along the bottom of the screen, revealed only
while the modifier key is held. Two beams travel in from the screen edges and
collide at the battery percentage — green from the left, red from the right.
Modules sit on that beam and the beam funnels into them.

```
LaserBar.qml                  the panel, one per screen, plus the data sources
├── BeamSide.qml   ×2         the two rails: band, wave strands, core line
├── CollisionEffects.qml      the payoff where they meet
└── BarSlots.qml              places the groups and binds everything they take
    └── BarGroup.qml  ×3      one capsule per side: left, centre, right
        ├── BarShell.qml      the capsule's geometry - plate, lips, filament
        └── your widget       one or more, side by side
```

A **group** is a capsule. A **widget** is a thing inside one. There are three
groups — left, centre, right — and widgets within a group are ordered by `pos`.
Today: `left: 1 workspaces`, `centre: 1 clock`, `right: 1 music, 2 wifi`.

A widget may take no width at all - the music widget collapses to zero with
no player - and the group leaves it out of the layout entirely rather than
drawing a separator at its zero-width boundary.

## Adding a widget: three steps

### 1. Write the widget

A widget is a plain `Item` that sizes itself. It does not know about the
capsule, the beam, the reveal or the battery.

```qml
import QtQuick

// What this is and why it exists.
Item {
    id: root

    // Read by BarGroup.
    property int pos: 1
    property bool groupWired: false
    // Bound by BarGroup, if you declare them. Declare only what you use.
    property bool active: false
    property real bodyHeight: 38

    implicitWidth: 40
    width: implicitWidth

    // ... your content, positioned from 0,0 ...
}
```

`ClockWidget.qml` is the smallest real example; `WifiWidget.qml` shows a widget
with inputs; `MusicWidget.qml` shows one that feeds itself from a service and
a subprocess, and collapses to nothing when there is nothing to show;
`WorkspaceWidget.qml` is the complicated one (a model, an animation and its
own internal dividers) and is not where to start.

A widget that takes its data from a service should still expose it as plain
properties with the service as the default — `MusicWidget`'s `title`,
`playing`, `levels` and friends — so a fixture can assign them and render
the widget with nothing on the bus. `cavaFeed: false` in the music fixtures
exists for exactly that: without it the live analyser overwrites the pinned
bands.

### 2. Declare it in `LaserBar.qml`

Inside the `BarSlots` block, in the group you want:

```qml
BarGroup {
    slotSide: "centre"

    DndWidget   { pos: 1 }
    ClockWidget { pos: 2 }
}
```

That gives a DND button to the left of the clock, in the middle capsule. `pos`
orders widgets within the group; the numbers need not be contiguous.

### 3. Register the file in `treeFor`

In `modules/home-manager/display/sway/quickshell/default.nix`:

```nix
"${d}/components/DndWidget.qml" = themedQmlFile variant ./components/DndWidget.qml;
```

**This one fails silently.** The QML tree is generated file-by-file; a
component that is not listed simply does not exist at runtime, and the error
you get is `DndWidget is not a type` with no hint that the file is sitting
right there on disk.

## Making a widget clickable

Wrap whatever should react in a `BarButton`:

```qml
BarButton {
    width: 28 * root.uiScale
    height: root.bodyHeight
    tint: root.railColor
    enabled: Dnd.available
    onClicked: Dnd.toggle()

    Text { anchors.centerIn: parent; text: "DND" }
}
```

That is the whole contract - hover and press feedback, the pointer cursor
and the click all come with it. `enabled` is Item's own property: set it
false for an action that is not available and the feedback goes with it.
`MusicWidget.qml`'s disc is the worked example.

Two things are worth knowing about how the pointer gets there at all:

- **The bar takes the pointer only while it is revealed.** `LaserBar.qml`
  gives the panel an input region the size of the panel while `active`, and
  a zero-sized one otherwise. The cost is that mod+click along the bottom
  70px does not drag a window while the bar is up.
- **The click arrives while the modifier is still held**, because that is
  the only time the bar is on screen. sway forwards a button press over a
  layer surface to the client rather than treating it as a
  `floating_modifier` drag, which is what makes this work at all. Keyboard
  focus is never taken (`focusable: false`), so the held modifier keeps
  doing its job underneath.

A mask is a texture rendered at its item's own size, so a circular mask on
a 30px item comes out as a visible octagon — `MusicWidget`'s cover sets
`layer.textureSize` to 4x to get a round edge. `antialiasing` and
`layer.samples` do not help.

A button whose feedback plate sits under opaque content will never be seen
- make the button a few pixels larger than the content, the way the music
disc does, so the highlight shows as a ring around it.

## The widget contract

`BarGroup` reads these from a widget:

| Property | Meaning |
|---|---|
| `pos` | Order within the group. Required — a child without it is ignored. |
| `width` | What the widget occupies. The group sums these to size the capsule. |
| `groupWired` | Scratch flag the group sets. Declare it, do not touch it. |
| `boundedEnds` | Optional. `true` asks for a separator at the capsule's ends. |
| `accentFromX` / `accentToX` | Optional. A span, in widget coordinates, to wash in the rail's colour. |
| `reservedWidth` | Optional. See *Widgets that change width*. |

`BarGroup` **binds** these into a widget, if the widget declares them. Every
write is guarded, so a widget that omits one is not broken by its absence:

| Property | Meaning |
|---|---|
| `active` | True while the bar is revealed. Gate timers and animations on it. |
| `bodyHeight` | The capsule's inner height. |
| `uiScale` | Multiply every dimension by this. See *Sizes and screens*. |
| `railColor` | Green or red, depending on which rail covers this group. |

`BarSlots` binds the same way into a *group*: `coverLeft`, `coverRight`,
`panelWidth`, `active`, `strokeColor`, `wireColor`, `wireColorAfterSeam`,
`seamX`, `railColor`. A group does not set those itself.

## Rules that are not negotiable

These are scars. Each one cost a debugging session.

1. **Nothing may run while the bar is closed.** It is shown only while a key
   is held. Gate timers on `active`. The clock's 1 Hz tick was re-rendering a
   layer FBO once a second, all session, for a clock nobody could see.

2. **No `layer.effect` on an item whose size changes.** `RevealMask` wraps
   every group in a layer whose texture is exactly the item's size, so an item
   that resizes mid-animation reallocates and re-renders that texture every
   frame. This is why a group whose widgets change width uses a fixed
   reservation with the capsule centred inside it, rather than resizing.

3. **No `Canvas`.** Qt rasterises it on the CPU and re-uploads a texture every
   repaint — measured at 110% CPU here against 7% idle. Use `Shape` +
   `ShapePath` with `preferredRendererType: Shape.CurveRenderer`.

4. **A `Shape` inside a widget only draws data it had at load.** A
   `ShapePath` whose `PathSvg`/`PathPolyline` data comes from anything that
   changes — a property written from JS, a function the binding calls, a
   point list — draws *nothing at all*, silently, while the identical path
   written as a QML literal draws fine. It was checked from both ends: the
   generated path string, logged every frame, was valid, and pasting one of
   those logged strings back as a literal rendered it. `BeamSide` escapes
   this because it builds its strands in a `Repeater` that pushes each
   `ShapePath` into the `Shape` by hand *after* the data exists — copy that
   pattern, or draw with `Rectangle`s, which is what `MusicWidget`'s wave
   does. Budget a whole session if you ignore this one: there is no warning
   to grep for.

5. **No positioners (`Row`, `RowLayout`) for anything that animates.** Use
   explicit `x` arithmetic. `StatusPanel.qml` documents a case where a
   positioner silently stopped laying out and stacked every child at `y: 0`.

6. **Do not make `BeamSide` rebuild its strands more often than its own tick.**
   A module animating its width changes its pinch span every frame; rebuilding
   five full-screen strand polylines at display rate on top of the wave's own
   30fps saturates the loop and the wave visibly stalls. `pinchSpans` changes
   are deliberately picked up on the next tick instead.

7. **One `BeamSide` per side.** Two leave a visible seam where they meet and
   duplicate the blurred glow layer.

## Sizes and screens

**Every dimension on the bar is written in 1080p-equivalent pixels and
multiplied by `uiScale`.** Write `implicitWidth: 40 * uiScale`, not
`implicitWidth: 40`. Declare `property real uiScale: 1` and `BarGroup` binds
the real value in, the same way it binds `active`.

`LaserBar` derives it from the output's logical height, clamped to 1..3. A
compositor that scales a HiDPI output hands the bar logical pixels and it
stays 1; an unscaled 4K output reports its full height and the bar doubles,
which is the case it exists for.

Two things follow from this that are easy to miss:

- **Font sizes must be rounded**: `font.pixelSize: Math.round(19 * uiScale)`.
  `pixelSize` is an int, and assigning a real to it is an error at load time,
  not a warning.
- **Anything that samples along a length must scale its step too**, or a
  bigger screen silently costs proportionally more work. `BeamSide` walks the
  beam in `3 * uiScale` increments so the point count stays constant.

`LASERBAR_UI_SCALE` pins the factor, and `laserbar-preview.sh` takes a
resolution as its fourth argument, so both can be checked without the display:

```sh
scripts/laserbar-preview.sh tests/laserbar/current-bar.qml /tmp/4k.png 0.5 3840x2160
```

## Theming

Colours come from `@token@` substitution — see `modules/lib/qml-theme.nix` for
the table and `quickshell/default.nix` for the per-variant values. Use
`@capsuleInk@` for marks on the plate. Never hardcode a colour that should
follow the theme; there are two variants (dark and light) and they are
generated into two separate trees.

If you add a token, default it in `qml-theme.nix`. `modules/nixosconf/greetd.nix`
and the lock-screen variant call the same function and render none of these
components, so a required argument there breaks both.

## Testing

The repo has no unit-test framework. The bar is verified by rendering it for
real and asserting on pixels.

```sh
scripts/laserbar-preview.sh tests/laserbar/<fixture>.qml /tmp/out.png 0.62
scripts/laserbar-probe.sh /tmp/out.png <x> <y> <w> <h> --near '#rrggbb' 25
```

`laserbar-preview.sh` evaluates the themed tree out of the **working tree**
with `nix eval` (not the installed `~/.config` copy), drops the fixture in as
`shell.qml`, runs nested sway on the wlroots headless backend, reveals the bar
over its IPC, and screenshots with `grim`. The third argument pins the battery
so the collision always lands at the same x. `LASERBAR_RETRACT=1` captures the
hidden state instead. A `<out>.log` is written next to the png.

Probe modes: `--near` for flat areas, `--dominant r|g|b` for the beam (whose
strands move every frame), `--darker-than` for "there is ink in this band",
and `--diff` between two renders for anything whose claim *is* a difference.

Write a fixture per thing you are testing — `tests/laserbar/` has one per
component and several per behaviour. Fixtures use a blue background
(`#FF2040A0`) precisely so the plate, the near-black outline and the
background are all distinguishable from each other.

**Check your probe actually fails without the fix.** Several probes in this
repo's history passed against renders that never happened or landed on the
wrong pixel. A probe whose coordinates you worked out on paper is a guess
until you have seen it go red.

`scripts/laserbar-cpu.sh <fixture> <seconds>` samples quickshell's CPU with the
bar held open. Compare against the current commit, back to back, in the same
session — the absolute number drifts with what else the machine is doing.

## Before you call it done

```sh
git add <the files you touched>   # nix ignores untracked files, so an
                                 # unadded .qml is invisible to flake check.
                                 # NOT -A: this tree usually holds unrelated
                                 # work in progress.
nix flake check
```

`nix flake check` does **not** force `xdg.configFile.*.text`, so it passes even
when a generated QML file throws. Check the generated text directly, for both
variants:

```sh
nix eval --raw '.#homeConfigurations.personal.config.xdg.configFile."quickshell/widgets-dark/components/DndWidget.qml".text'
```

Never discard its stderr: a failed eval returns an empty string, which then
greps clean for leftover `@tokens@` and looks exactly like a pass. Check the
exit status and the line count too.

Then a real switch, which is the user's call to run:

```sh
home-manager switch --flake .#personal && systemctl --user restart quickshell-widgets
```

## Adding a panel zone

The control panel (`components/ControlPanel.qml`) is the sheet summoned out of
the clock. It is not a bar widget and the three steps above do not apply to it,
but every rule in "Rules that are not negotiable" does, plus two of its own.

**Split the zone in two.** Anything that reads the system is a non-visual
`*Model.qml` plus a renderer that takes plain properties, the way
`StatusModel.qml` backs `StatusPanel.qml`. That split is not tidiness: it is
what makes the zone testable. The renderer can be driven from a literal in a
fixture, so a render test asserts on values you chose instead of on what this
machine's radios, diary or disks happen to be doing. Every zone fixture in
`tests/laserbar/panel-*.qml` works this way.

**Gate every repeating timer.** Bind `active` to the panel being open and hang
the poller off it. The panel shells out to khal, df, curl, geoclue, nmcli,
bluetoothctl and powerprofilesctl, and it is shut almost all of the time.
This is checked, not remembered:

```sh
python3 scripts/laserbar-gating.py
```

It reads the generated tree, exempts one-shots (`repeat: false`) and exempts
`NotificationServer` by name — a notification centre that only listened while
you were looking at it would be a list of things you had already seen.

Measured, panel open: `laserbar-cpu.sh tests/laserbar/panel-full.qml` is about
a point above `current-bar.qml`. Shut, it is 0.0%. If either number moves, a
timer escaped.

### The things that cost a session

- **The sheet and its tail are one `Shape`** (`PanelSheet.qml`). Two
  translucent fills overlapping leave a visible seam, and a `Rectangle` cannot
  omit its border along part of an edge — so a rectangular sheet always drew a
  line across the funnel's mouth. The path is a literal in 1080p units with the
  whole `Shape` scaled by `uiScale`, because a `ShapePath` whose data changes
  draws nothing, silently (rule 4).
- **One animated inset clip drives every docked transition**, and the clipper
  moves while the sheet inside it is pinned by an equal and opposite offset.
  The panel must not shift a pixel when it docks: mod is pressed dozens of
  times an hour.
- **Resting state must stand down while a transition runs.** Re-attach was
  broken by `.detached` pinning the bar invisible while the rails animated back
  in behind it. `tests/laserbar/panel-roundtrip.qml` is the regression test —
  summon, detach, re-attach must be pixel-identical to a plain summon.
- **A `Process` whose binary does not exist never emits `onExited`** — it fails
  to *start*. Give-up logic hung off exit never runs. `MetricsModel` forked a
  doomed `nvidia-smi` eight times in two seconds before this was understood;
  it now counts attempts instead.
- **Tooltips need their own `PopupWindow`.** The sheet clips its children to
  its corners, so a tip drawn inside can never cross the top edge, which is
  exactly where a top-row tile's tip goes.
- **`@glassBg@` is the bar's capsule material, not the panel's ground.** At 40%
  it works in dark and fails in light, where base05 ink ends up floating on
  whatever the wallpaper is. The panel has `@panelBg@`, passed per variant.
- **Nothing meaningful may be carried by `base0B` at small sizes.** Light's is
  `#94E1B0`; a 3px dot or a 12px label in it is invisible on cream. Active
  toggles take an accent *fill* with `@onAccentInk@` on top, and the calendar's
  event dots are ink.

Render the light variant too — it has failure modes dark cannot show:

```sh
LASERBAR_VARIANT=light scripts/laserbar-preview.sh tests/laserbar/panel-full.qml /tmp/light.png 0.62
```

`docs/previews/laser-bar-panel.html` is the approved design; open it beside a
render. `docs/superpowers/specs/2026-10-19-laser-bar-panel-design.md` says why
each part is the way it is.

## Related

- `docs/superpowers/specs/2026-10-16-laser-bar-modules-design.md` — the design
  this was built from, including the behaviour that must not change.
- `docs/superpowers/specs/2026-10-19-laser-bar-panel-design.md` — the control
  panel's design, including the anti-goals it must not drift into.
- `BeamSide.qml` — read its comments before touching the beam. They record two
  separate performance regressions and why the current shape is what it is.
