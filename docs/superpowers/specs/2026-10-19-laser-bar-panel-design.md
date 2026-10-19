# Laser bar panel — design

Date: 2026-10-19
Branch: `feat/laser-bar-panel`
Approved visual reference: `docs/previews/laser-bar-panel.html` (open in a browser)

## Intent

The laser bar shows only while mod is held. Everything it can tell you has to
fit on a strip and has to be read in the second or two the key is down. There
is no room on it for a calendar, no room for a volume slider, and no home at
all for notifications — mako throws a toast and the information is gone.

This adds a panel that grows out of the clock in the middle of the bar: one
glass sheet carrying the things worth sitting with. It is summoned from the
bar while mod is held, and it survives the key being released, so you can
read it and click it with the bar gone.

It also makes Quickshell the notification daemon. That is not a side effect
of wanting a notification list — it is the only way to get one with actions
and grouping, and it means mako is removed.

## Goals

- One surface for: system toggles, the clock, weather, a usable calendar with
  events, CPU/GPU/RAM, disk space, notifications, and audio output.
- Summoned and dismissed without ever leaving the keyboard.
- Reads as part of the bar, not as a separate window that happens to be near it.
- Themed entirely by darkman, through the same base16 palette as everything else.

## Non-goals

- The Mobile zone is a labelled placeholder this round. The KDE Connect module
  is later work and nothing in this design should assume it exists.
- **Notification toasts are not in this round.** Quickshell owns the bus and
  collects notifications into the center; it pops nothing. The user has taken
  this decision knowing the consequence: mako and Quickshell cannot both own
  `org.freedesktop.Notifications`, so from the switch until toasts are built
  there are no popups at all and a notification is only visible by opening
  the panel. Leave the server's popup surface unimplemented rather than
  half-built.
- No notification *history* beyond what the session holds. Persistence across
  restarts is not in scope.
- No settings UI. Everything configurable lives in Nix.
- **The desktop widgets stay.** `shell.qml`'s standing `Clock {}`, `Music {}`
  and `Calendar {}` on the wallpaper are untouched by this work, even though
  the panel carries its own clock and calendar. Reconciling them is the
  user's follow-up, not this round's.

## Anti-goals

Things that would make this a failure even if it worked:

- **Six identical rounded cards.** The reference dashboard that started this
  conversation is exactly that, and so is most of the genre. The panel is one
  sheet; zones are divided by hairline beams that fade at both ends — the
  laser used as a ruler. Keep it.
- **The panel moving when it docks or undocks.** Mod is pressed dozens of
  times an hour. Any geometry change on attach or detach reads as a twitch.
  This was tried in the preview and explicitly rejected.
- **Anything running while the panel is closed.** The bar's first
  non-negotiable rule applies here with more force: this panel polls weather,
  metrics, disks and calendars. All of it must be gated.

## Constraints

- **Quickshell/QML**, inside `modules/home-manager/display/sway/quickshell/`,
  themed by `@token@` substitution through `modules/lib/qml-theme.nix`.
- **Every rule in `docs/adding-a-bar-widget.md` § "Rules that are not
  negotiable" applies**, in particular: no `Canvas`; no `layer.effect` on
  anything that resizes; a `Shape` only draws data it had at load; no
  positioners for anything that animates; all dimensions in 1080p-equivalent
  pixels multiplied by `uiScale`.
- **Colours come only from `modules/lib/palette.nix` base16 slots.** No
  invented hexes. The one derived value in the preview is "ink on an accent
  fill", which is `base00` in dark and `base07` in light.
- `flake check` does not evaluate generated QML text — see the repo's
  standing note on that. The headless render harness in `tests/laserbar/` is
  the real check.

## Behaviour

### Summoning

The bar is revealed by holding mod, which sway currently binds as `Insert` in
`modules/home-manager/display/sway/default.nix:169-170`. **That binding is
wrong and is being corrected to `Mod4` as part of this work.**

With the bar up, either click the clock pill or press `n`. The panel grows
out of the clock in 0.2–0.3s, attached to the bar by the tail.

### Detaching

Releasing mod hides the bar as it always does, and the panel stays. It
detaches with its own animation. Pressing mod again re-attaches it.

### Dismissing

Click outside it, press Escape, or change workspace. All three dismiss it.

### Output

It opens on the output whose bar was clicked, and only there. (Builder's call,
not stated by the user — flagged here as an assumption.)

## The animations

Four named transitions between three resting states (`attached`, `detached`,
`gone`). The preview implements all four; copy the timings from it.

**The panel's geometry never changes in any of them.** Only the tail, the
rails, the clock pill and the panel's shadow move.

| Transition | From → to | What moves |
|---|---|---|
| Summon | gone → attached | Tail shoots up out of the clock (130ms), then the panel opens from the tail's mouth by clip/mask so content never stretches (280ms), content rises, and one laser wipe crosses left to right. ~300ms total. |
| Detach | attached → detached | Rails run back out to the screen edges, the clock pill goes, the tail is drawn back down into it, the panel's shadow deepens. |
| Re-attach | detached → attached | The exact inverse. |
| Dismiss, docked | attached → gone | Content drops out, then the panel closes back toward the clock. |
| Dismiss, free | detached → gone | **A different animation.** With no bar and no clock on screen, collapsing toward the bottom centre is a retreat into nothing. The panel sinks back a step (scale 0.965) and fades, ~190ms. |

A lesson from building the preview that is worth carrying over: resting-state
styling must stand down while a transition runs, or it fights the animation.
The re-attach was broken for exactly this reason — the detached state pinned
the bar invisible while the rails animated back in behind it.

## The tail

The tail is the single most load-bearing visual element: it is what makes the
panel read as part of the bar rather than a window near it. It went through
several rounds and the final form matters.

- **Wide funnel, not a pin.** 300px at the mouth, necking to roughly the
  clock pill's width.
- **Made of the same material as the panel** — same glass, same backdrop blur.
  An approximated fill reads as a different colour; this was visibly wrong in
  the light theme until the tail became the same material rather than a shape
  tinted to match.
- **It overlaps the panel's bottom edge** so that edge does not draw a line
  across the funnel's mouth. The panel's border runs *into* the flanks.
- **Only the two flanks are stroked.** No line across the mouth.
- **It reaches the clock** and runs a few pixels behind the pill, which hides
  where the flank strokes terminate.
- It carries the beam's green glow, so it belongs to the bar optically too.

In QML this is a `Shape` + `ShapePath` with `CurveRenderer`, not a `Canvas`,
and — because rule 4 says a `Shape` only draws data it had at load — the
funnel geometry must be a literal, with the open/close animated by a mask or
clip rather than by rewriting the path.

## Layout

Three columns, two rows. Proportions in the preview are approved but not
sacred.

```
┌────────────────┬──────────────────────┬─────────────────┐
│ toggle grid    │ CPU / GPU / RAM      │ Mobile (stub)   │
├────────────────┴───────────┬──────────┼─────────────────┤
│ clock · date · weather     │  disks   │ notifications   │
│ calendar                   │          │                 │
│ events for selected day    │          │ ─── audio out   │
└────────────────────────────┴──────────┴─────────────────┘
```

Zones are separated by 1px beams that fade at both ends. There are no cards.

### Toggles

Seven, as icon tiles in a 4-wide grid, no text on the buttons. The name shows
in a tooltip on hover — **and the tooltip must be able to overhang the panel.**
The panel clips to its rounded corners, so in Quickshell the tooltip has to be
its own `PopupWindow`; a tooltip drawn inside the panel can never cross its
top edge.

| Tile | Backend | Notes |
|---|---|---|
| Do not disturb | Quickshell's own notification server | Suppresses toasts; the center still collects. |
| Power profile | `powerprofilesctl` | **Three states, not two.** Cycles power-saver → balanced → performance, icon changes per state. `scripts/swaync/power-toggle.sh` already does this cycle. |
| Night light | gammastep | **New module.** Not currently installed anywhere; the old `scripts/swaync/night-shift-toggle.sh` drove `hyprsunset` under Hyprland. |
| Wi-Fi | NetworkManager (`nmcli`) | |
| Bluetooth | bluez (`bluetoothctl`) | `hardware.bluetooth` and blueman are already on. |
| Dark mode | darkman | |
| Lock | existing lock IPC | **Not a toggle.** Drawn wide, spanning two columns, outlined rather than filled, because it is an action. |

Active state is an accent fill with ink on top. It must not be carried by text
colour alone: `base0B` in light is `#94E1B0`, which is illegible as 12px text
on cream.

Night light and dark mode **must not share the crescent icon.** Night light is
a sun shedding warm wavy light; the crescent belongs to dark mode alone. They
collided in an early draft and the row became unreadable.

### Clock, date, weather

In the head of the calendar zone. Time large in Orbitron (the bar clock's
face), date beneath it, weather to the right as temperature plus condition
and location.

Weather is **Open-Meteo** — no API key, no account — and the location
**follows the laptop via geoclue** rather than being hardcoded.

### Calendar

Fully interactive, not a read-only month:

- Previous/next month arrows, with the month name centred in a fixed-width
  box so the arrows do not shuffle as the name's length changes.
- A **"Today" button that is always visible**, dimming to inert once you are
  actually on today. An earlier version only revealed it once you had
  navigated away, which means you had to already be lost to find the way back.
- Click any day to select it. Today stays marked even when another day is
  selected.
- Days carrying events get a dot under the number.
- Below the grid: the selected day's events, time + title, with a 2px colour
  bar keyed to which calendar it came from.

The backend already exists. `modules/home-manager/calendar-sync.nix` syncs
five ICS subscriptions with vdirsyncer into khal, and
`quickshell/components/Calendar.qml` is an existing standalone `PanelWindow`
with `monthCells` and `upcomingEvents`. Selecting a day re-runs `khal list`
for that date.

**That desktop widget keeps running** (see Non-goals), so the panel cannot
simply take it over. Lift the khal-reading and month-building logic into a
shared non-visual model — the way `StatusModel.qml` backs `StatusPanel.qml` —
and let both the desktop widget and the panel render it. Do not write a
second khal parser.

At most three events are listed, then "and N more". One caveat the user raised
and did not resolve: on a busy day this hides the evening. Builder's call —
see Open questions.

The events block must be pinned to the bottom of its zone with the slack
collecting above it, or it jumps 30px every time you page into a month that
draws six rows instead of five.

### Metrics, disks, mobile

- CPU/GPU/RAM as horizontal meters with Orbitron percentages, plus a
  sparkline. `Sparkline.qml` already exists; reuse it.
- GPU is the open one: this machine has both nvidia (`modules/nixosconf/nvidia.nix`)
  and amdgpu. See Open questions.
- Disks as vertical fill bars in the narrow column — the only shape that fits
  there — with a free-space total underneath.
- Mobile is a dimmed labelled placeholder. It should look deliberately unfinished.

### Notifications and audio

Quickshell takes over `org.freedesktop.Notifications` and **mako is removed**
(`modules/home-manager/display/sway/mako.nix`, and its import). This means the
popup toasts become ours to design as well as the center — that is part of
this work, not a follow-up.

The center lists notifications with app name, title and body, grouped by app,
with per-item dismiss and a "Clear all". Audio sits below a beam line at the
bottom of the same column: output device picker and volume, over
PipeWire/WirePlumber.

## Open questions for the builder to settle

These are flagged rather than answered because reasonable builders could
differ and none of them changes the shape of the work:

1. **Event list length.** Three plus a count hides the evening on a busy day.
   Scrolling the list, or raising the cap when the month grid is short, are
   both reasonable.
2. **GPU source.** nvidia via `nvidia-smi` and amdgpu via sysfs
   `gpu_busy_percent` behave differently and have different costs. Picking
   one, or showing whichever is active, is the builder's call.
3. **Multi-output.** Assumed to open only on the output whose bar was clicked.
4. **`Insert` → `Mod4`.** The user is correcting the binding; confirm it
   landed before wiring `mod+n`.

## What the preview does and does not settle

`docs/previews/laser-bar-panel.html` is approved for layout, colour,
typography, icon set, interaction and all four animations. It is a browser
mockup: its timings and easings transfer, its implementation does not. The
QML has different rules, and the bar's non-negotiables beat anything the
HTML does.

## Calls made while writing this up

Settled here rather than asked, because a sensible builder could have decided
them either way without changing what gets built. Worth a glance:

- **Size.** 940×700 in 1080p-equivalent pixels, multiplied by `uiScale` like
  everything else on the bar. The 700 is not padding: the calendar column
  needs it, and at 620 the events list was silently clipped by the panel's
  own rounded-corner clip.
- **Keyboard focus.** The panel takes keyboard focus on demand, not
  exclusively, so Escape reaches it without the panel stealing keys from
  whatever is underneath while it sits there detached.
- **Click-outside.** Dismissal on an outside click needs an input region
  covering the output while the panel is open; it should not block clicks
  from reaching the window underneath on the same press.
- **The lock screen** dismisses the panel rather than drawing over it.
- **Toggle state is not persisted** across a Quickshell restart. Each toggle
  reads its real backend on open, so there is nothing to persist.
- **`mod+n`** is a normal sway binding (`bindsym --no-repeat Mod4+n exec
  quickshell ipc …`) rather than anything the panel listens for itself.
