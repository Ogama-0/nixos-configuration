# Theming: one palette, two variants, darkman

Every colour on the `personal` desktop comes from **one file**,
`modules/lib/palette.nix`, and gets rendered twice — once dark, once light.
`darkman` picks which rendering is live and swaps it at sunrise and sunset.

There is no Stylix. It used to generate all of this from a wallpaper; it was
removed deliberately (`docs/superpowers/specs/2026-10-14-drop-stylix-runtime-theming-design.md`
says why). Nothing in the repo derives colours from an image any more, so a
colour you want changed is a colour you edit by hand, in one place.

## Where everything lives

| File | Job |
|---|---|
| `modules/lib/palette.nix` | **THE place to change colours.** Plain `#RRGGBB`, three groups per variant: `ui`, `terminal`, `status` |
| `modules/lib/theme-colors.nix` | Shim that strips the leading `#` from `ui`, because QML wants `#AARRGGBB` and consumers prepend their own alpha byte |
| `modules/lib/qml-theme.nix` | The `@token@` → colour substitution table for all Quickshell QML |
| `modules/lib/alacritty-colors.nix` | Renders `terminal` as the two `colors.toml` files |
| `modules/lib/helix-auto-theme.nix` | The two `auto.toml` bodies — helix is the one app that does *not* follow ANSI |
| `modules/lib/zellij-theme.nix` | The two zellij themes, which need true colour rather than ANSI slots |
| `modules/lib/quickshell-tree-link.nix` | Repoints `~/.config/quickshell/widgets` at one of the two trees |
| `modules/home-manager/darkman.nix` | The switch itself: five dark/light script pairs, plus the timezone sync |
| `modules/home-manager/display/gtk.nix` | GTK plumbing, with the keys darkman owns deliberately left unset |
| `modules/lib/timezone-coords.nix` | Lat/lng per timezone, shared with the greeter |

## Who follows what

Not everything reads the same group, and that split is the thing most likely
to surprise you:

- **`ui`** → the Quickshell bar, widgets, control panel and lockscreen, the
  greeter, mako, vicinae. Via `theme-colors.nix`. Follows the base16 slot
  convention (`base00` darkest ground → `base07` lightest text,
  `base08`–`base0F` accents), and consumers assume those *roles*. Changing a
  slot's value is fine; swapping its role will look wrong everywhere.
- **`terminal`** → alacritty, and through alacritty most TUIs (bat, yazi, …),
  because they draw with the terminal's own ANSI colours.
- **`status`** → the oserv status widget's up/degraded/down/muted semantics.
  Deliberately *not* base16 slots: the two palettes disagree about where each
  hue lives, and several light slots fail their contrast floors outright.
- **helix** is the exception to "TUIs follow the terminal" — it gets real
  themes (`horizon-dark` / `onelight`), because `term16_*` only reaches the 16
  ANSI slots and loses all syntax nuance.
- **zellij** is the other exception — it paints its chrome in true colour, so
  it has to be told explicitly, and it takes its ground from `ui` but its
  light accents from `terminal`.

Not covered at all: the swaylock module keeps its own hardcoded colours and
does not switch.

## How a switch actually happens

1. `darkman` decides the mode from lat/lng. It does **not** use geoclue —
   `usegeoclue: false`, and `darkman.nix`'s `darkmanTimezoneSync` activation
   script derives coordinates from `/etc/localtime` instead, writing
   `~/.config/darkman/config.yaml` on every switch. That makes the mode follow
   `time.timeZone`, which is what you actually change when you travel.
2. On transition it runs five scripts per direction:
   - **alacritty** — `install` the right `colors.toml`. Alacritty live-reloads.
   - **helix** — `install` the right `auto.toml`, then `pkill -USR1` helix.
   - **zellij** — `install` the right `auto.kdl` (for *new* sessions) **and**
     `zellij action set-<mode>-theme` for every *running* one.
   - **gtk-theme** — three `dconf write`s: `color-scheme`, `gtk-theme`,
     `icon-theme`.
   - **quickshell-theme** — repoint the `widgets` symlink at
     `widgets-dark`/`widgets-light` and restart `quickshell-widgets.service`.

Force a mode by hand while testing:

```
darkman get          # current mode
darkman set dark     # or light
darkman toggle
```

## The rule that explains most of this code

**Anything darkman rewrites at runtime must NOT be managed by
`xdg.configFile`.** A managed path is a read-only symlink into the Nix store,
and darkman cannot replace it. Every module that participates has a comment
saying so, because each one learned it separately:

- `alacritty.nix` seeds `colors.toml` **only when missing**, from an
  activation script rather than `xdg.configFile`.
- `helix.nix` does the same for `themes/auto.toml`.
- `zellij/default.nix` leaves `themes/` unmanaged for the same reason.
- `darkman.nix` keeps `services.darkman.settings = { }` **on purpose** —
  home-manager's own darkman module manages `darkman/config.yaml` via
  `mkIf (cfg.settings != {})`, so a single setting there would turn the file
  darkman must write into a store symlink.
- `gtk.nix` declares neither `gtk.theme` nor `gtk.iconTheme`, and never sets
  `color-scheme`: home-manager's gtk module writes both `settings.ini` and the
  dconf keys, so every activation would stomp whatever mode darkman last
  selected. darkman owns all three keys.
- The `quickshell/widgets` symlink is made by an activation script, not
  `xdg.configFile`, and only *when it is not already a symlink* — darkman owns
  which tree it points at, and relinking unconditionally would drop a daytime
  desktop onto the dark tree and force a second restart on every switch.

The mirror-image rule: seeding must be conservative. Seeding
unconditionally (rather than only-when-missing) hands a daytime desktop the
dark theme on every `switch` until darkman's next run corrects it.

## Changing a colour

1. Edit `modules/lib/palette.nix`. Nothing else.
2. `nix flake check` — then see *Validating a change* below, because that
   check is much weaker than it looks.
3. `home-manager switch`, then `darkman toggle` twice to see both variants.

## Adding a new app to the theme

1. Render its colour file from `palette.nix` in a new `modules/lib/<app>-*.nix`.
   Take the values from the palette; never re-type a hex code.
2. Seed it from the app's own module with an activation script, **only if the
   file is missing**, and leave the path unmanaged.
3. Add a `darkModeScripts.<app>` / `lightModeScripts.<app>` pair in
   `darkman.nix` that installs the right file.
4. If the app caches the theme in memory, add a reload. Check what signal it
   actually honours — and see the `comm` trap below before writing a `pkill`.

## Adding a QML token

Add it to **both** lists in `modules/lib/qml-theme.nix`, and give it a
default. `modules/nixosconf/greetd.nix` and the lockscreen variant call the
same function and render almost none of these components, so a *required*
argument breaks both callers.

Two token rules that cost real time:

- **`replaceStrings` takes the first match, so a duplicated token name is
  silently dead.** `@sheetBg@` is named that and not `@panelBg@` precisely
  because `@panelBg@` already existed for `StatusPanel`; the sheet quietly
  inherited the older token's value for one commit.
- **Several values cannot be derived from `colors` alone** and are passed
  per-variant from `quickshell/default.nix` instead: `capsuleFill`/
  `capsuleInk`, `onAccentInk`, `sheetBg`, the status colours. The reason is
  always the same — `base00` is pure black in dark but the *cream ground* in
  light, so "ink" is `base00` in one variant and `base07` in the other. One
  fixed slot cannot mean the same thing in both.

## Gotchas already paid for

**A green `nix flake check` does not mean your QML evaluates.** `flake check`
only shallow-checks `homeConfigurations` — it never forces the generated
`xdg.configFile` *text*, which is where every `@token@` substitution happens.
Force it explicitly:

```
nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath
```

**An un-`git add`ed file makes that check green against a tree without it.**
Flakes copy only tracked files into the store. A new `modules/lib/*.nix` you
have not staged is simply absent from the evaluation, so the check passes by
testing the old tree. `git add` before you believe a result.

**`pkill -x <name>` silently matches nothing when the comm is truncated or
wrapped.** darkman's helix reload matches `'(\.hx-wrapped|hx)'` because the
nixpkgs wrapper means `comm` is *not* `hx` — a bare `pkill -x hx` matches
nothing and reports success. Same trap as the process-exporter matchers in
`docs/adding-a-server-service.md`. Every such reload also ends in `|| true`:
"no instance running" is the normal case and must not surface as a failed
transition.

**Qt apps that never read `QT_QPA_PLATFORMTHEME` stay dark forever.** Without
it the app never asks the portal for the colour scheme, so it ignores darkman
entirely. `display/vicinae.nix` sets `QT_QPA_PLATFORMTHEME=gnome` on its
systemd service for exactly this; it needs no darkman script, because Qt then
follows the portal's `SettingChanged` live.

**zellij needs telling twice.** `auto.kdl` only decides what a *new* session
starts in — and zellij picks that by asking the terminal for its background
over OSC 11, falling back to its built-in radioactive-green theme when no
answer arrives. Running sessions need the separate `zellij action
set-<mode>-theme` call, one per session. A session started before the last
switch still holds the old config and will refuse, hence `|| true`.

**`ln -sfn` is not enough for the widgets symlink.** Against a *real*
directory it creates the link *inside* it (`widgets/widgets-dark`), leaving
`quickshell -c widgets` unable to find `shell.qml` — which is exactly the
state a machine is in the first time the dark/light split is applied.
`quickshell-tree-link.nix` handles that, and *moves aside* rather than deletes
anything that is not a symlink.

**"Failed to create wl_display" after a switch is a stale systemd user
environment, not a QML bug.** The user manager is still holding the old
session's `WAYLAND_DISPLAY`. Fix the environment, don't debug the QML.

## Contrast: measured, but not enforced

The light values were picked against a measured floor — `>= 7:1` (WCAG AAA)
for `light.terminal` against its own ground, `3:1` for filled status bands and
`4.5:1` for the 11px latency column. Every ratio in `palette.nix`'s comments
was computed by hand at the time.

**Nothing re-checks them.** This repo has no test suite (see
`tests/laserbar/README.md`), so a low-contrast pick ships silently. If you
change a light value, re-measure it by hand.

Why the alphas are what they are, since they interact with contrast: the
control-panel sheet is nearly opaque in both variants because at 80% a bright
window underneath read straight through and sat behind the notification text.
In dark it uses `base01` rather than `base00` — a 94%-black sheet on a black
wallpaper has no edges, and the panel vanished leaving its own dividers
floating in space.

## Validating a change

```
# 1. stage the files you touched - flakes ignore untracked ones.
#    Name them; this tree usually holds unrelated in-progress work,
#    so `git add -A` would sweep that in too.
git add modules/lib/palette.nix

# 2. the real check: forces the generated configFile text
nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath

# 3. switch, then see both variants
darkman toggle
darkman toggle
```

For the bar and panel specifically, render them rather than eyeballing the
live desktop — `tests/laserbar/README.md` and `docs/adding-a-bar-widget.md`
cover the headless harness, which evaluates the themed tree out of the
**working tree** instead of whatever the last switch produced.

## Related

- `docs/superpowers/specs/2026-10-14-drop-stylix-runtime-theming-design.md` —
  why Stylix went away and what replaced each thing it did.
- `docs/superpowers/specs/2026-09-29-auto-theme-switch-design.md` — the
  original darkman design.
- `docs/adding-a-bar-widget.md` — the token table from a widget author's side.
- `docs/greeter.md` — the greeter renders the same QML through the same
  `qml-theme.nix`, but with store paths, because the greeter user cannot read
  `/home`.
