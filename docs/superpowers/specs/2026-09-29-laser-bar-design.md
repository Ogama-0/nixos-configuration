# Quickshell laser bar — design spec

## Context

The `personal` profile currently runs `sway` with an `i3status-rust` bar
(`modules/home-manager/display/sway/barbar.nix`), toggled on/off via bare
`Mod4` (`exec swaymsg bar mode toggle`). The goal is to prototype a
replacement bar built in Quickshell (already used in this repo for other
desktop widgets — wallpaper, clock/weather, music, calendar, lockscreen —
via the persistent `quickshell-widgets` systemd service and its
`shell.qml` scope). The old bar is left in place during the prototype
phase; it's triggered from a temporary key (`Insert`) rather than bare
`Mod4`, so the existing bar-toggle keybinding and the old bar's
mouse-hover reveal are both left completely untouched while comparing
the two side by side. The bare-Mod key can be repointed at the new bar
later, once the prototype is validated.

The requested visual: two laser beams grow from the left and right
screen edges and meet at an x-position determined by battery percentage
(e.g. 80% battery → they meet 80% of the way across the bar). The beams
appear on `Mod` press and retract on release, fast (0.1–0.2s). Modules
(starting with just a time/date display, more later) are meant to look
like they were always sitting on the bar, progressively uncovered as the
passing beam sweeps over their position — not faded in after the fact.

This design intentionally targets only `sway` / the `personal` profile,
and only the top-bar position, per explicit instruction to compare it
against the existing bar before deciding on a permanent position/switch.

## Goals

- New Quickshell component rendering the two-laser battery bar at the
  top of the screen.
- Press-and-hold `Mod4` reveals it; release retracts it; total beam
  travel animation 100–200ms.
- Laser color: white on light theme (`stylix.polarity == "light"`),
  black on dark theme (`stylix.polarity == "dark"`) — literal, not a
  contrast choice.
- A time/date module rendered as a rounded pill, horizontally centered
  on screen (fixed position, independent of the battery-driven meeting
  point).
- The module is always laid out but clipped by a reveal mask tied to
  the beams' current width, so it's progressively uncovered as a beam
  sweeps past its position, and re-covered symmetrically on retract —
  no separate fade animation.
- The masking approach must be reusable for future modules placed
  anywhere along the bar, not hardcoded to the clock pill.
- Old `i3status-rust` bar and its config remain untouched, still
  reachable by mouse-hover at the screen edge.

## Non-goals

- Removing or replacing the old i3status-rust bar/config.
- Bottom-bar positioning (top only, for now).
- Additional modules beyond time/date (structure should allow them
  later, but only time/date ships now).
- Hyprland/i3/oserv profiles — sway/personal only.

## Architecture

No new Quickshell instance or systemd service. The new component joins
the existing always-running `quickshell-widgets` service:

- New file: `modules/home-manager/display/sway/quickshell/components/LaserBar.qml`
- New file: `modules/home-manager/display/sway/quickshell/components/RevealMask.qml`
  (reusable wrapper — see "Reveal mask" below)
- Registered in `shell.qml`'s `Scope` next to `Wallpaper`, `Clock`,
  `Music`, `Calendar`, `Lock`.
- Themed via the existing `withThemeColors` string-replace mechanism in
  `modules/home-manager/display/sway/quickshell/default.nix`: add a
  `@laserColor@` placeholder resolved from `config.stylix.polarity`
  (`"#FFFFFF"` when `"light"`, `"#000000"` when `"dark"`). The pill
  keeps using the existing `@cardBg@`/`@cardBorder@`/`@clockColor@`/
  `@dateColor@` placeholders already defined there.
- Controlled by IPC, same pattern as the existing `wallpaper` target:
  `IpcHandler { target: "laserbar"; function reveal(): void {...}; function hide(): void {...} }`.
  (Named `reveal`, not `show` — `show` collides with the `quickshell ipc
  show` subcommand name and is silently misparsed.)
- Sway wiring (`modules/home-manager/display/sway/default.nix`): the
  existing `keybindings` attrset (including bare `"${modifier}"`) is
  left untouched. A new `extraConfig` block (a sibling of `config`, not
  nested inside it — home-manager's sway module keeps them separate)
  adds two raw `bindsym` lines on a temporary key, since the
  `keybindings` attrset has no way to express a `--release` variant:
  - `bindsym Insert exec quickshell ipc -c widgets call laserbar reveal`
  - `bindsym --release Insert exec quickshell ipc -c widgets call laserbar hide`

## Battery data

A `Timer` (30s interval, matching the `battery` block's poll cadence
already used in `barbar.nix`) drives a `Process` that reads
`/sys/class/power_supply/BAT*/capacity`. If no `BAT*` device exists,
`batteryFraction` defaults to `0.5` (symmetric bar) rather than
erroring — no other error handling needed, this is a laptop-only
feature.

## Panel & beams

- `PanelWindow` anchored `top`+`left`+`right` (full screen width),
  `WlrLayershell.layer: Overlay`, `exclusionMode: Ignore` (doesn't
  reserve space / push other windows), `focusable: false`,
  `mask: Region {}` while idle so clicks pass through underneath
  (same technique as `Wallpaper.qml`'s background layer).
  `implicitHeight` sized to fit the pill (~64px).
- `active: bool` property, flipped by the two IPC functions.
- **Left beam**: `Rectangle` anchored to the panel's left edge,
  ~5px thick, `width: active ? batteryFraction * panelWidth : 0`,
  horizontal gradient (faint at the screen edge → saturated at the tip).
- **Right beam**: mirrors it from the right edge,
  `width: active ? (1 - batteryFraction) * panelWidth : 0`, gradient
  faint-to-saturated in the opposite direction.
- Both use `Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }`.
  Fixed duration regardless of distance means both tips always land at
  the meeting point simultaneously, and total beam travel stays inside
  the 100–200ms budget in both directions.
- A small blurred flare at the meeting point (`x = batteryFraction * panelWidth`)
  fades in with beam extension to sell the "collision."
- Glow/bloom via a blurred duplicate layer (`QtQuick.Effects.MultiEffect`,
  already used for masking in `Wallpaper.qml`, so known-available in
  this quickshell build).
- Color: `@laserColor@` for both beams and the flare.

## Reveal mask (modules)

Because `leftWidth + rightWidth` always equals the full panel width at
full extension regardless of `batteryFraction`, the union of the two
lit regions always sweeps the *entire* bar by the time the beams meet.
This is what module reveal rides on:

- `RevealMask.qml` takes `coverLeft` (bound to the left beam's current
  width) and `coverRight` (bound to the right beam's current width) and
  wraps arbitrary child content positioned anywhere on the bar.
- A position `x` within the wrapped content is visible if
  `x <= coverLeft OR x >= (panelWidth - coverRight)`.
- Implemented as two mirrored clip regions over identical content (one
  revealed left-to-right tracking `coverLeft`, one right-to-left
  tracking `coverRight`); where both would show, the content is
  identical so there's no visible seam.
- Because `coverLeft`/`coverRight` are the same animated properties
  driving the beams, no separate opacity/fade animation is needed —
  reveal and retract are both just consequences of the existing beam
  width animation. This wrapper is what future modules will reuse.
- Known behavior consequence (confirmed acceptable): a module's reveal
  timing depends on which beam's front reaches its position first, not
  on the module's own distance from center — since beam duration is
  fixed at 150ms regardless of distance traveled, the beam responsible
  for more ground moves faster. This matches the "light sweeping across
  a bar" metaphor.

## Time/date module

- A rounded pill, styled like the existing `Clock.qml` card
  (`@cardBg@` background, `@cardBorder@` border, `@clockColor@` time
  text, `@dateColor@` date text), horizontally centered on screen
  (fixed position — independent of `batteryFraction`).
- Wrapped in `RevealMask` so it's uncovered/covered exactly in sync
  with beam travel, per above.
- Time/date text updated via the same `Timer`-driven
  `Qt.formatDateTime` approach `Clock.qml` already uses.

## Testing / validation

No test suite in this repo (`nix flake check` + real switch is the
established validation pattern). For this feature:

1. `nix flake check`
2. `nix run nixpkgs#home-manager -- switch --flake .#personal`
   (or a full `nixos-rebuild switch --flake .#personal` if testing live)
3. `systemctl --user restart quickshell-widgets`
4. Manually verify:
   - Press/hold/release `Insert` shows and retracts the beams within
     the 0.1–0.2s budget.
   - Beams meet at the position matching current battery %.
   - The center pill reveals/covers in sync with whichever beam's
     front passes it first.
   - Toggling `stylix.polarity` between `"dark"`/`"light"` and
     re-switching swaps the laser color between black/white correctly.
   - Old i3status-rust bar's mouse-hover reveal and its bare-`Mod4`
     toggle keybinding are both unaffected.
