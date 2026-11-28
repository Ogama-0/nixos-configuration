# Notifications

Quickshell *is* the notification daemon. It owns `org.freedesktop.Notifications`;
mako and swaync are gone, and two daemons cannot share that bus name. The
`scripts/swaync/*.sh` files are senders now, not a daemon.

Everything lives in `qml/notification/`:

| File | Role |
|---|---|
| `NotificationServer.qml` | the bus, the list, grouping, persistence, the DND rule |
| `NotificationToasts.qml`  | the popup layer surface, top right |
| `NotificationPane.qml`    | the centre, inside the control panel |
| `NotificationHead.qml`    | icon · app · count · relative time, one row |
| `NotificationRow.qml`     | one notification's text, shared by both surfaces |
| `BeamWire.qml`            | the laser bar's wire, at notification scale |

`NowClock.qml` sits in `qml/common/` because the centre and the toasts both
need it and neither owns it.

**The volume, mic and brightness readouts are NOT here.** They are SwayOSD -
see the bottom of this file.

## The rules that are not obvious

**The server is not gated on the panel being open.** A centre that only
listened while you were looking at it would be a list of things you had
already seen. That is why the server is a separate component from the pane.

**Do-not-disturb stops the interruption, never the collecting.** The whole
rule is one pure function, `shouldPost(transient, dnd)`: a transient goes
through whatever DND says, anything else is suppressed while it is on.
Asserted by `tests/laserbar/panel-notify-dnd.qml`.

**The wire is `@accentLineColor@`, not `@greenColor@`.** They are the same
colour in dark and deliberately are not in light. base0B there is a pale
mint that measures **1.24:1** against the plate, so the wire and the life
bar were being drawn correctly and could not be seen; the count badge, which
is a *fill* with dark ink on it, stays `@greenColor@` and reads either way.
Anything on this surface that paints the accent a few pixels wide takes the
first token. See `docs/theming.md`.

**Urgency is read off the hint.** `Critical` never auto-expires and takes
`@downColor@`; `Low` gets a grey wire and a shorter life. A battery at 3%
that cleared itself after six seconds is the failure this prevents. A pack
keeps the *strongest* urgency it holds, or a routine notification packing
into a critical one would quietly hand it an expiry. Asserted by
`tests/laserbar/panel-notify-urgency.qml`.

**A click resolves in this order, and no other branch exists:**

1. dragged more than `tapSlop` → it was a gesture. Nothing.
2. packed **and** collapsed → expand. The app action never fires: the action
   belongs to one notification and a pack is several.
3. packed, open, pressed within `headBand` of the top → collapse.
4. otherwise → `activated(record)`, and the toast retires with it.

`ControlPanel.actionTable` resolves step 4. It is data, not a switch: `match`
takes the record and returns a bool, `run` does the thing, first match wins,
the last row matches everything. Adding an app is adding a row.

Two things it gets right that are easy to get wrong: the KDE Connect row
matches **SMS only** (`summary === "Messages"`), because *everything* from the
phone arrives relayed under that app name and a battery warning should not
open the compose surface; and the sender-actions row invokes the action whose
identifier is `default`, not `actions[0]`, which is merely whichever one the
sender happened to list first.

## Traps

Every one of these was paid for once already.

**`recordFor()` runs inside a binding.** It is called from the
`notifications` property, which re-evaluates whenever anything arrives or is
dismissed. A `Date.now()` in there resets the timestamp of *every*
notification each time a new one comes in. Arrival times are stamped once in
`onNotification` into `seenAt` and looked up afterwards; `seenAt` is mutated
in place, because reassigning it would invalidate the same binding.

**Reassigning a JS-array model destroys and recreates EVERY delegate**, not
just the one that changed. Any per-toast state declared in the delegate is
therefore reset whenever any *other* toast arrives. The life clock has to
live in `live` as an absolute `expiresAt`; a delegate-local accumulator or
animation silently never fires, and on a busy desktop nothing ever expires.

**…and `modelData` is a SNAPSHOT of the model element, not a handle on it.**
The sweep pushes `expiresAt` forward in place while a toast is held, and a
binding on `modelData.expiresAt` never sees any of it - the bar kept draining
under the pointer. Read `root.live[toast.index]` instead; the binding already
re-evaluates on every `tickNow`, so in-place changes land on the next tick
without anything having to notify. These two rules are a pair: put state in
the model, *and* read it back out of the model.

**Nothing leaves this surface without `retire()`.** The ceiling used to be
enforced by slicing the array, which made the fourth toast disappear between
two frames — and took any toast already mid-exit with it, cutting that
animation off wherever it had reached. `live` is therefore allowed to be
longer than `maxShown`: what is capped is how many are *alive*, and the
reaper clears the leaving ones when their exit is done. Asserted by
`tests/laserbar/panel-toasts-ceiling.qml`.

**"Is this toast new?" is a flag in the model, not a clock.** It was
`Date.now() - born < 150` in the delegate, which is a wall-clock race in a
render path: the window closes whether or not a delegate was built inside
it, so one stall between `show()` and the Repeater meant the entrance
silently never played. `entry()` takes an `arrive` argument that only
`show()` passes, and the first delegate built from the entry clears it in
place — so a *rebuilt* delegate, which is already on screen, does not
re-fly. You cannot observe the flag from a caller: a Repeater builds its
delegates synchronously on model reassignment, so it is already spent before
`show()` returns.

**A loop that reassigns `live` cannot also be iterating it.** The sweep
collects the ids that have run out and retires them after the walk. It used
to `return` on the first one, which quietly cost every entry *after* it that
tick's `expiresAt += elapsed` — a held toast sitting below one that timed
out stopped being held for 100ms — and meant only one toast could ever
retire per tick however many had run out.

**A Timer gated on something stops advancing its own bookkeeping.** The
sweep's `lastTick` only moves inside `onTriggered`, and the sweep only runs
while a toast is up. Without re-stamping it in `onRunningChanged`, the first
tick after a quiet stretch measures `elapsed` across the whole gap and hands
all of it to any held toast as extra life.

**`clip: true` clips to a bounding RECTANGLE, not to rounded corners.** This
one bit twice on the same plate: the wire painted straight through the corner
arcs at the top, and the life bar ran out past them at the bottom. The wire
tapers its amplitude to nothing over `endRamp` at each end; the life bar is a
3px clip across a rectangle that carries the plate's own `radius`.

**Qt clamps `radius` to half the shorter side.** Shrinking that rounded
rectangle to show the level therefore straightened its corner once it
narrowed past twice the radius - visible only in the last moment of the
drain. The rectangle keeps its full size and the *clip window* shrinks.

**`scale` is uniform.** With `transformOrigin: Item.Left` it narrowed the
life bar and thinned it at the same rate. Width, not scale.

**A `ShapePath` cannot be a `Repeater` delegate.** Repeater only instantiates
Items, and a ShapePath used directly fails *silently* - no strands render at
all, and since the core is near-straight by design the wire just looks like
the flat rule it replaced. Wrap each in an `Item` and push it into the
Shape's `data`. `BeamSide.qml` documents the same workaround.

**Animating a property that has a binding destroys the binding.** The arrival
animates `offsetX` and `fadeIn`, never `plate.x` or `plate.opacity`, which are
bound to the drag.

**`left` is `Item.left`.** Naming a property that fails at load with "Cannot
override FINAL property".

**The toast window is twice the plate's width.** A thrown toast travels its
own width and then some, and a child leaving the layer surface is clipped by
it. The extra width is empty and stays click-through because
`mask: Region { item: column }` covers the plates and not the window.

## Speed

Worth knowing where the time actually goes, because the obvious guess is
wrong. Measured on `personal`:

| | |
|---|---|
| spawning any store binary (floor) | 9 ms |
| `Notify` DBus round-trip, server replies | 25–80 ms |
| `notify-send` end to end | 38–113 ms |
| the arrival animation | **this is what you feel** |

The pipeline is not slow. A toast that seems to lag is a long entrance, and
**travel distance matters as much as duration** - a plate crossing a third of
the screen reads as slow however fast it is moving. Every duration lives in
one block at the top of `NotificationToasts.qml`.

A toast on screen costs about **3%** of a core. Getting there:

| | |
|---|---|
| where it started | 12.8% |
| life bar animating `width` continuously (60Hz repaint of the whole plate, Shape included) | **−7** |
| dropping `Shape.CurveRenderer` and coarsening the sample step | −1.6 |
| …but CurveRenderer is the only thing that antialiases the strands, so it is back | +0.4 |

The lesson is the frame rate, not the mechanism: *any* continuously running
animation repaints the whole toast for as long as it runs, and width versus
transform barely mattered. The life bar is derived from the 100ms sweep with
a 100ms `Behavior` smoothing between steps.

Two things that are not the renderer and still cost per frame:

**The layer surface is quantised.** `implicitHeight` rounds the column up to
a 48px step. Bound straight to `column.implicitHeight` it asked the
compositor to resize *and reconfigure* the surface on every frame of a pack
expand, because the plate animates its height. The slack is transparent and
sits outside `mask`, exactly like the empty half of the width.

**BeamWire's sample grid is not rebuilt by the phase.** `t` and the end
taper depend only on height, reveal and `endRamp`; the phase moves `x` and
nothing else. Recomputing the ramp nine times a tick (eight strands plus the
core) was most of the arithmetic in the only thing on a toast that runs
continuously.

**And the state file coalesces.** `saveSoon` is 250ms, not 0. Every arrival
and every dismissal lands there and each run flattens, serialises and writes
all fifty records — clearing a group of twelve used to be twelve of those.
`restart()` collapses a burst into one write of the final state.

Measuring this needs care — the desktop's idle CPU swings by ten points or
more on its own (the music card's spectrum), which is wider than the effect.
Use **matched long windows** and hold a toast open with a `critical`
notification, which by design never expires.

## SwayOSD

Volume, mute, mic and brightness are SwayOSD, not notifications.

They used to be sent as transient notifications so the toasts would show
them. SwayOSD is the surface a reading actually wants - one pill, no history,
no actions - and for volume `swayosd-client` performs the wpctl call
*itself*, so each key is one command rather than a script that made the
change, read the level back and parsed `wpctl get-volume`.

**But it performs it in the SERVER.** `swayosd-client --output-volume raise`
is a DBus call, not a local one, so the daemon is in the critical path of
*changing* the volume and not only of drawing it. If `swayosd.service` is
down - and `Restart=always` with `StartLimitBurst=5` means five crashes in
ten seconds leaves it `failed` - the key does nothing at all, where the old
wpctl script at least changed the volume and only lost the readout. So
`volume-key` asks SwayOSD and falls back to `wpctl` when the client exits
non-zero. The fallback is silent: there is no volume LED on this laptop and
nothing left to draw with, but silent and working beats silent.

**Brightness is the opposite split: brightnessctl changes it, SwayOSD only
draws it**, through `--custom-progress`, exactly as the phone volume does.
`swayosd-client --brightness raise` is a *linear* 5% of the raw backlight
range (`BRIGHTNESS_CHANGE_DELTA` in its source) with no knob for either
half, and these keys were `brightnessctl --exponent=2 s +10%`. On an OLED
panel the exponent is the whole point - it puts the small steps at the
bottom of the range, where you want fine control and where a linear 5% of
maximum is a huge relative jump. This way round is also fail-soft: the
brightness has already changed by the time SwayOSD is asked for anything.

- `modules/features/desktop/swayosd.nix` — `ogama.desktop.swayosd.enable`,
  defaulting to `sway.enable`. `topMargin = 0.78`: the toasts own the top
  right and the laser bar owns the bottom edge.
- `lib/swayosd-style.nix` — the two stylesheets, rendered from
  `lib/palette.nix`, same shape as `alacritty-colors.nix`.
- `modules/features/desktop/sway/default.nix` — the keybindings and the two
  wrapper scripts, `volume-key` and `brightness-key`. **Nothing here sends a
  notification for them.** Having both would put two things on screen for
  one keypress.

`style.css` is rewritten by darkman and so must NOT be managed by
`xdg.configFile` — see `docs/theming.md`. It is seeded only when missing and
installed by the darkman script pair, which also `try-restart`s the daemon,
because GTK reads its stylesheet once at startup.

Two things learned the hard way:

**`--custom-message` and `--custom-progress` are two different OSDs.**
Passing both draws the message and then replaces it with the bar a frame
later. The phone-volume binding sends progress only; the phone glyph is what
distinguishes it from this machine's volume.

**A travelling wave is not reachable from a stylesheet.** Measured in an
isolated SwayOSD: an `opacity` keyframe moves hundreds of pixels between
frames, while neither `background-position` nor a `background-image` flipbook
moves a single one. GTK's animation engine runs fine; background images are
simply not among the properties it will interpolate or switch.

## Testing

```
scripts/laserbar-preview.sh tests/laserbar/panel-toasts.qml /tmp/t.png
scripts/laserbar-preview.sh tests/laserbar/panel-toasts-ceiling.qml /tmp/c.png
scripts/qml-logic-test.sh tests/laserbar/panel-notify-dnd.qml 'DND_RULE ok'
scripts/qml-logic-test.sh tests/laserbar/panel-notify-relay.qml GROUPS
python3 scripts/laserbar-gating.py
```

`panel-notify-urgency.qml` and `panel-toasts-ceiling.qml` print their
assertions but instantiate a `PanelWindow`, so they need the render harness
rather than the offscreen one — read the sentinels out of the `.log` beside
the png (`URGENCY ok`, `CEILING ok`).

**Run the render ones with `LASERBAR_VARIANT=light` too, and measure rather
than look.** Every colour bug this surface has had was light-only and none
of them was obvious in a screenshot: the life bar's corner, and then the
wire and the life bar being drawn in a green that was 1.2:1 against their
own plate. A render plus `magick ... txt:` on the pixels you care about is
the only check there is — see the crop recipe below.

To see a state the fixtures do not reach - a nearly-empty life bar, say -
set `expiresAt` close to now and `held = true` so the sweep cannot retire it,
then measure the result in the PNG rather than eyeballing a zoom:

```
magick shot.png -crop 420x1+1540+66 +repage txt: | …
```

SwayOSD can be exercised without touching the running one by giving the
nested compositor its own session bus — `dbus-run-session -- sway …`, since
the real server already owns the name.
