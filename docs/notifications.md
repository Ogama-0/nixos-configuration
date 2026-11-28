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

Measuring this needs care — the desktop's idle CPU swings by ten points or
more on its own (the music card's spectrum), which is wider than the effect.
Use **matched long windows** and hold a toast open with a `critical`
notification, which by design never expires.

## SwayOSD

Volume, mute, mic and brightness are SwayOSD, not notifications.

They used to be sent as transient notifications so the toasts would show
them. SwayOSD is the surface a reading actually wants - one pill, no history,
no actions - and `swayosd-client` performs the wpctl/brightnessctl call
*itself*, so each key is one command rather than a script that made the
change, read the level back and parsed `wpctl get-volume`.

- `modules/features/desktop/swayosd.nix` — `ogama.desktop.swayosd.enable`,
  defaulting to `sway.enable`. `topMargin = 0.78`: the toasts own the top
  right and the laser bar owns the bottom edge.
- `lib/swayosd-style.nix` — the two stylesheets, rendered from
  `lib/palette.nix`, same shape as `alacritty-colors.nix`.
- `modules/features/desktop/sway/default.nix` — the keybindings. **Nothing
  here sends a notification for them.** Having both would put two things on
  screen for one keypress.

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
scripts/qml-logic-test.sh tests/laserbar/panel-notify-dnd.qml 'DND_RULE ok'
scripts/qml-logic-test.sh tests/laserbar/panel-notify-relay.qml GROUPS
python3 scripts/laserbar-gating.py
```

`panel-notify-urgency.qml` prints its assertions but instantiates a
`PanelWindow`, so it needs the render harness rather than the offscreen one —
read the sentinels out of the `.log` beside the png.

Run the render ones with `LASERBAR_VARIANT=light` too. The life bar's corner
bug was only ever visible in light.

To see a state the fixtures do not reach - a nearly-empty life bar, say -
set `expiresAt` close to now and `held = true` so the sweep cannot retire it,
then measure the result in the PNG rather than eyeballing a zoom:

```
magick shot.png -crop 420x1+1540+66 +repage txt: | …
```

SwayOSD can be exercised without touching the running one by giving the
nested compositor its own session bus — `dbus-run-session -- sway …`, since
the real server already owns the name.
