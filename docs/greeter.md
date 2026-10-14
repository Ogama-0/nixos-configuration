# The greeter

Graphical login for the `personal` profile: `greetd` runs `sway`, that sway runs
a Quickshell surface that mirrors the lockscreen designs. This is the working
reference for changing it. The original design rationale is in
`docs/superpowers/specs/2026-10-06-quickshell-greeter-design.md`.

## Where everything lives

| Path | What it is |
| --- | --- |
| `modules/nixosconf/greetd.nix` | The whole NixOS side: substitutes the QML, installs it to `/etc/greeter/`, configures `greetd`, grants polkit rights |
| `modules/qml/GreeterDark.qml` | Dark surface. Stencil panels, neon edge-glow, Orbitron |
| `modules/qml/GreeterLight.qml` | Light surface. Frosted glass pills, falling snow, Nunito |
| `modules/qml/components/GreetdSession.qml` | The auth conversation. Shared by both surfaces |
| `pkgs/greetd-proxy/proxy.py` | stdio↔socket bridge *and* the dark/light variant picker |
| `pkgs/greetd-proxy/test_proxy.py` | Its tests. pytest-style functions, so `python3 -m unittest` silently runs none |
| `modules/lib/qml-theme.nix` | The `@token@` substitution, shared with the home-manager lockscreen |
| `modules/lib/theme-colors.nix` | The base16 palettes. No hex literals for palette colours anywhere else |
| `modules/lib/timezone-coords.nix` | Timezone → lat/lng, for sunrise/sunset |

The two surfaces are deliberately *not* the same design recoloured. Dark is flat
angular stencil over the Arcane artwork; light is frosted glass over a
watercolour. Behaviour is shared; appearance is not.

## How a login actually happens

1. `greetd` starts `sway -c /etc/greeter/sway.conf` as the `greeter` user.
2. That sway runs `greeter-launch`, which calls `greetd-proxy --theme` to decide
   dark or light from the local sunrise/sunset, and launches `quickshell -p` on
   the matching surface.
3. The surface spawns `greetd-proxy` as a `Process` and talks newline-delimited
   JSON to it over stdin/stdout.
4. The proxy owns greetd's length-prefixed socket framing and relays both ways.
5. On success the surface sends `start_session`, greetd kills the greeter, and
   the real session starts.

**If quickshell fails to start, `greeter-launch` execs `agreety` instead.** That
fallback is the main thing standing between a bad QML edit and a machine you
cannot log into. Do not remove it. Note it only covers quickshell failing to
*launch* — a surface that starts and then misbehaves is not covered, which is
why `GreetdSession` handles the helper dying mid-authentication itself.

**The fallback is gated on a marker file, not on quickshell's exit status.**
greetd kills the greeter the instant it honours `start_session`, so a
successful login also ends with quickshell exiting non-zero — the two cases are
indistinguishable from the status alone. `greetd-proxy` creates
`$GREETD_STARTED_MARKER` just before it relays `start_session`; `greeter-launch`
exports that path and only execs `agreety` when the marker is absent. Keying off
the exit status instead flashed agreety onto VT1 on *every* login, where it
promptly crashed as the real session took the VT.

`Ctrl+Alt+F2` is a plain getty. That is the real last resort.

## The constraints that bite

- **The `greeter` user cannot read `/home/ogama`.** Every asset, font and QML
  path must resolve to the Nix store or `/etc/greeter/`. This is why
  `greetd.nix` passes store paths into the substitution where the home-manager
  module passes home paths.
- **Fonts must be in `fonts.packages`** in `greetd.nix`. The greeter sees
  nothing from home-manager. Currently Corpta, Orbitron, Nunito, Inter.
- **`modules/lib/qml-theme.nix` is shared with the lockscreen.** Adding a
  `@token@` there affects `modules/home-manager/display/sway/quickshell` too.
- **No new hex literals for palette colours.** Change
  `modules/lib/theme-colors.nix`. Surface-specific accents (the dark greeter's
  magenta/cyan/amber) are the exception and live at the top of their own file.
- **`greetd-proxy` is stdlib-only Python.** No third-party imports.

## The focus ring

Both surfaces use the same model, and it is the part most likely to surprise you.

`root.focusedField` is a five-slot ring: `0` username, `1` password, `2..4` the
power controls. `root.focusSlot(i)` wraps and moves, `root.ringKey(event)` is
called from every key handler and returns whether it consumed the event.

Three things are load-bearing:

- **The ring state decides what is highlighted, not `activeFocus`.** A plain
  `Item` does not keep active focus across a key handler. Power controls bind
  their lit state to `root.focusedField === 2 + index`.
- **While the ring points at a power control, `content` holds the real focus**
  and activates the control on its behalf, from `content`'s own `Keys.onPressed`.
- **Shift+Tab arrives two ways.** Qt's Wayland plugin sends `Key_Tab` with
  `ShiftModifier`; other paths send `Key_Backtab`. `ringKey` treats both as
  backwards. Handle both or it walks the wrong way.

Both `TextInput`s set `activeFocusOnTab: false` so Qt's own tab chain cannot
move focus out from under the ring and leave `focusedField` stale.

## Qt and Quickshell gotchas already paid for

- **`cursorVisible: false` does not stick.** `TextInput` forces it back to true
  internally on every focus-in. Both fields reassert it in
  `onCursorVisibleChanged`. Remove the handler and the caret returns.
- **A `MouseArea { anchors.fill: parent }` directly inside a `Column`** silently
  disables the Column's positioning entirely — "Column will not function" — and
  the children vanish. Wrap the Column in an `Item` and make the hit area a
  sibling.
- **Animating a property breaks its binding.** The rejection shake used to target
  `passPanel.x`; with anchors the anchor won and nothing moved, and with an `x`
  binding it would have destroyed the binding on first use. Both surfaces now
  animate a dedicated `shakeOffset` that the position binding adds in.
- **`Behavior` cannot drive a `readonly property`.**
- **Inside a `component`, a `content` identifier resolves to that component's own
  default-property alias**, not an outer `id: content`. Map to scene coordinates
  with `mapToItem(null, …)` instead.
- `Shape`/`ShapePath` need `import QtQuick.Shapes`. `cursorShape` is unrelated.
- Quickshell appears to discard a `Process`'s stderr, and `console.log` does not
  reliably reach the journal. To observe something, make it change the UI or
  write to a file.
- **`onAccepted` handing focus to another field lets the same Return land
  twice.** Enter on the username field focuses the password field *during* that
  keypress, so holding Enter (or double-tapping it) auto-repeats straight into
  `passwordField.onAccepted` — once per repeat, ~25×/second. Each one submitted
  an empty password, and greetd takes an empty password to PAM, which rejects it
  and then holds everything for its multi-second fail delay: one stray Enter
  bought a bogus "wrong password" and a visible stall on the way in. Both
  surfaces now refuse an empty password in `submitPassword()`. Any new field
  that submits on Enter needs the same thought.
- **Do not disable an input to mean "busy".** The password field used to be
  `enabled: !session.busy`. PAM's fail delay is multiple seconds, so a
  rejected attempt left the field disabled and unfocused for that whole
  window, silently eating everything typed into it - no dots, no warning.
  Anyone who starts retyping before the rejection clears submits a truncated
  password and is rejected a second time, which is indistinguishable from
  mistyping twice. The field now stays live; `submitPassword()`'s own busy
  guard is what prevents a second submit, and `root.keepAfterRejection()`
  strips only the characters that were actually submitted so the retry
  survives. Both surfaces compute it from `submittedText`, which neither
  failure handler mutates, so the two handlers agree whichever order Qt runs
  them in.
- **A reply is not always a new event.** greetd acks `start_session` with a
  plain `{"type":"success"}`, the same shape as an authentication success. The
  surface treated it as one and re-fired `authenticated()`, so
  `success → authenticated → startSession → success` spun as fast as the pipe
  allowed; in production only greetd killing the greeter cut it short.
  `GreetdSession.starting` latches once `start_session` is away.

## Previewing without a rebuild or a reboot

There is no committed harness; rebuild it in a scratch directory when needed.
The approach, which works and is worth repeating:

1. Render the themed QML by calling the **real** `modules/lib/qml-theme.nix` via
   `nix eval`, passing the working-tree file as `surface`. Never hand-substitute
   the `@token@` colours — the point is to preview exactly what a rebuild
   installs. Check for leftovers with `grep -oE '@[a-zA-Z]+@'`.
2. Point `@greetdProxyBin@` at a stub running
   `pkgs/greetd-proxy/proxy.py --mock <password>` — an in-process fake greetd
   that already exists in the repo for this purpose.
3. Point `@systemctlBin@` at a stub that appends to a log file, so a misclick
   cannot power the machine off, and so the action is observable.
4. Run it either in a nested sway window (`WLR_BACKENDS=wayland`) for real
   keyboard and mouse, or headless (`WLR_BACKENDS=headless`) plus `grim` for a
   screenshot.
5. Fonts from `fonts.packages` are not installed on the running system until a
   rebuild, so a preview silently falls back to a default face. Point
   `XDG_DATA_DIRS` at the built font packages' `share` directories.

Harness limits worth knowing before you trust a negative result:

- A headless seat has **no pointer device**. `swaymsg seat … cursor` returns
  success and does nothing, so hover and click cannot be tested headless. Use
  the nested window.
- `wtype` works (virtual-keyboard protocol) but **drops the first key of every
  invocation**. Put a whole sequence in one `wtype` call.
- Short animations are hard to catch in a single frame. Temporarily lengthen the
  duration *in the rendered copy* to photograph a mid-flight state.

## Validating a change

```
nix flake check
nix eval --raw .#nixosConfigurations.personal.config.system.build.toplevel.drvPath
cd pkgs/greetd-proxy && nix shell nixpkgs#python3Packages.pytest -c pytest -q
```

Then, on the machine itself, prefer `nixos-rebuild test` over `switch` for the
first run of a greeter change: `test` does not touch the boot entry, so a reboot
gets you back to a known-good greeter. Verify on a spare VT before trusting it.
