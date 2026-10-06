# Quickshell greeter on greetd for the `personal` profile

## Goal

Replace the bare getty login on `personal` with a graphical greeter that is
visually a sibling of the existing Quickshell lockscreens: the same
Zaun/Jinx dark design and Nausicaa/snow light design, picked automatically
by time of day, driving a real `sway` session through `greetd`.

## Background

Audited in this session: `personal` has no display manager at all. There is
no `services.displayManager.*` and no `programs.sway.enable` in
`host/personal/configuration.nix` — the machine boots to a getty and `sway`
is started by hand from the shell. `security.pam.services.quickshell-lock`
exists solely for the lockscreen.

The lockscreen is a `Scope` containing a `WlSessionLock`, implemented twice
(`modules/home-manager/display/sway/quickshell/components/LockDark.qml` and
`LockLight.qml`, ~620 lines each). The two are deliberately *not* recolors
of one another: dark is flat angular stencil panels with neon edge-glow and
an Orbitron clock over the Arcane artwork; light is a frosted-glass/snow
treatment. Authentication is a `PamContext` against the `quickshell-lock`
PAM service. Colors are injected at build time by `@token@` string
substitution in `quickshell/default.nix`, sourced for the lock variants from
`modules/home-manager/lib/theme-colors.nix` — a pure data file with no
home-manager dependency.

Runtime variant selection today is darkman (`modules/home-manager/darkman.nix`):
its `darkModeScripts`/`lightModeScripts` symlink `Lock.qml` to `Lock-dark.qml`
or `Lock-light.qml`. darkman is a *user* service of `ogama`, so it is not
running at greeter time and cannot be consulted.

Verified against the installed Quickshell 0.3.0: `Quickshell.Io` exports
`Socket`, `SocketServer`, `Process`, `SplitParser`, `StdioCollector`, and
`DataStreamParser`.

## Non-goals

- The `oserv`, `epita`, and `epita-light` profiles. `personal` only.
- Session selection. The greeter starts `sway` and nothing else.
- Replacing or restyling the lockscreens. They keep working exactly as they
  do now; this design only *moves* already-extracted shared components.
- Multi-user support beyond an editable username field. The field defaults
  to `ogama`.
- MPRIS/media display and the `systemctl --user restart quickshell-widgets`
  hook. Both are meaningless before a user session exists and are dropped
  from the greeter.

## Decisions taken during design

Each of these was presented with alternatives and chosen explicitly:

1. **Variant selection computes sunrise/sunset itself** rather than reading a
   state file written by darkman. No shared writable state, no permissions
   problem, correct on first boot. Accepted consequence: if the mode was
   manually toggled against the clock before shutdown, the greeter will not
   match the last desktop state.
2. **New `Greeter*.qml` files reusing already-extracted components**, rather
   than a full shared-component refactor or a single file with a
   `greeterMode` flag. Keeps a lockscreen that is still being iterated on
   untouched. Accepted consequence: panel/layout code is duplicated between
   lock and greeter and can drift.
3. **A stdio helper process for greetd IPC**, not hand-rolled framing in QML.
   See "Auth flow" for why QML alone is not sufficient.
4. **`sway` as the greeter compositor**, not `cage` — the greeter inherits
   output positioning, scale, and the `caps:escape` keyboard option, all of
   which matter on a screen whose entire purpose is typing.

## Architecture

### File layout

```
modules/lib/theme-colors.nix        moved from modules/home-manager/lib/
modules/lib/timezone-coords.nix     extracted from darkman.nix
modules/qml/components/             moved from .../quickshell/components/:
                                      BeamSide, GlassPill, ColorUtils,
                                      ClockModule, CollisionEffects,
                                      RevealMask, LaserBar
modules/qml/GreeterDark.qml         new
modules/qml/GreeterLight.qml        new
modules/nixosconf/greetd.nix        new
pkgs/greetd-proxy.nix               new
```

Two files move up out of home-manager because the NixOS greeter module must
read them and must not depend on home-manager evaluation. `theme-colors.nix`
is already pure data, so the move is mechanical. `timezone-coords.nix` is the
`timezoneCoords` attrset currently inlined in `darkman.nix`; `darkman.nix`
imports it after the extraction so the lat/lng table stays single-source.

The `@token@` substitution currently written as `withThemeColors` /
`withLockThemeColors` / `lockVariant` in
`modules/home-manager/display/sway/quickshell/default.nix` is factored into a
function in `modules/lib/` taking the palette, the asset paths, and the
binary paths as arguments. Both the home-manager quickshell module and the
NixOS greeter module call it. The home-manager module keeps passing home
paths; the greeter module passes Nix store paths.

### Variant selection

`greetd-proxy --theme` reads `/etc/localtime`, resolves the timezone the same
way `darkman-timezone-sync` already does (`readlink -f`, strip through
`/zoneinfo/`), looks the coordinates up in `modules/lib/timezone-coords.nix`
with Paris as fallback, computes today's sunrise and sunset, and prints
`dark` or `light`.

The greeter's sway config runs this once at startup and launches
`quickshell -p /etc/greeter/GreeterDark.qml` or `GreeterLight.qml`. The
decision is made once per greeter launch and is not re-evaluated while the
greeter is on screen.

### Auth flow

greetd's protocol is a 4-byte native-endian length prefix followed by a JSON
payload, over the socket named by `$GREETD_SOCK`. Quickshell's `Socket` is
text-oriented and `SplitParser` splits on a string marker; hand-rolling the
binary length header in QML only works while each payload stays under 128
bytes, because above that the length byte stops being representable as a
single UTF-8 byte. A password long enough to cross that boundary would break
authentication silently. This is why the design uses a helper.

`pkgs/greetd-proxy.nix` builds a small Python script (`writers.writePython3Bin`,
using `struct` for the framing — consistent with the plain-script idiom in
`scripts/`). It exposes newline-delimited JSON on stdin/stdout and translates
to and from greetd's framed protocol. The QML drives it with `Process` plus a
`SplitParser` on stdout — the same pattern `LockDark.qml` already uses for
`playerctl` and `curl`.

Sequence:

1. Username submitted -> `create_session` -> greetd replies `auth_message`
   with `auth_message_type: "secret"`.
2. Password submitted -> `post_auth_message_response`.
3. `success` -> `start_session` with `cmd: ["sway"]`. The greeter exits and
   the user session starts.
4. `error` with `error_type: "auth_error"` -> the QML clears the password
   field, returns focus to it, and sets the existing `showFailure` state. The
   proxy sends `cancel_session` followed by a fresh `create_session` for the
   same username, so greetd is never left mid-conversation.

`--mock` mode answers the same stdio protocol with canned responses and no
socket, so the greeter QML can be run inside a normal desktop session for
visual iteration without rebooting.

## Greeter UI

Carried over from the lock design: clock, date, the variant's artwork, and
the laser/glow chrome. Added: weather temperature, a power control row, and a
username field. Dropped: MPRIS media and the widgets-restart hook.

The weather fetch is the same `curl` call the lock uses. Network is up at
greeter time because NetworkManager is a system service, but the fetch can
race an unassociated wifi link, so the temperature element must render an
empty state rather than a placeholder or an error.

### Keyboard interaction

Fully operable without a mouse:

- Username field holds focus at startup, pre-filled with `ogama`, editable.
- Enter on username sends `create_session` and moves focus to password.
- Enter on password submits.
- Up/Down arrows move focus between the two fields at any time.
- Ctrl+A selects all in the focused field.
- On auth failure the password clears and focus returns to it.

### Selection and focus treatment

The dark password field renders no glyphs — it is `color: "transparent"` with
`selectionColor: "transparent"` and a hidden cursor, with alternating
magenta/cyan paint-drip dots standing in for characters. A conventional
selection rectangle has nothing to highlight there, so selection is expressed
differently per field and per variant.

**Dark — hard edges, no border-radius, matching the existing stencil panels:**

- Username selection: flat magenta block behind the glyphs, `selectedTextColor`
  knocked out to `#1C1E26`, so selected text reads as a stencil cut out of the
  accent rather than inverted text.
- Password selection: the drip dots drop their magenta/cyan alternation, all
  go magenta, and sit on a 2px cyan rule.
- Focus: the active field raises its neon edge-glow and gains a 2px magenta
  tick on its left edge; the inactive field drops to 35% opacity with the glow
  off.

**Light — soft and layered, consistent with the glass treatment:**

- Username selection: a frosted band, translucent pale fill at 2px radius with
  a faint inner border; `selectedTextColor` stays `base05` so it reads as a
  pane laid over the text, not an inversion.
- Password selection: dots unify to a single tone and dim slightly under the
  same frosted band.
- Focus: the active field brightens its glass panel and gains a thin cyan
  hairline underline; the inactive field stays flat and translucent.

## NixOS wiring

`modules/nixosconf/greetd.nix`, imported from `host/personal/configuration.nix`:

```nix
services.greetd = {
  enable = true;
  vt = 1;
  settings.default_session = {
    command = "${pkgs.sway}/bin/sway -c /etc/greeter/sway.conf";
    user = "greeter";
  };
};
```

Four things the module must handle explicitly, each of which fails silently or
confusingly if left implicit:

- **Assets from the Nix store, not `$HOME`.** The lock substitution points at
  `${config.home.homeDirectory}/nixos-configuration/assets/...`. The `greeter`
  user must not depend on reading `/home/ogama`, so the greeter substitution
  uses `${../../assets/lockscreen/...}` store paths.
- **System-level fonts.** Corpta and Orbitron are installed through
  `modules/home-manager/display/font.nix` and are invisible to the `greeter`
  user. They are added to `fonts.packages`.
- **Keyboard layout.** The `caps:escape` xkb option lives in
  `modules/home-manager/keyboard.nix`. The greeter's sway config needs its own
  copy, or Caps behaves differently at login than inside the session.
- **Polkit rule** permitting the `greeter` user to invoke `poweroff`,
  `reboot`, and `suspend` for the power control row.

QML files, the sway config, and the wrapper script are installed to
`/etc/greeter/` via `environment.etc`.

`personal` runs a hybrid Nvidia setup (`modules/nixosconf/nvidia.nix`), but
sway is launched today by typing `sway` with no flags and works, so the
greeter launches it the same way. If the greeter fails to start on the Nvidia
path, adding `--unsupported-gpu` is the first thing to try.

## Lockout safety

A greeter that crashes at boot means no graphical login, so three independent
layers are required:

1. The greeter sway config execs a wrapper script rather than `quickshell`
   directly. If quickshell exits nonzero, the wrapper execs `agreety`. There
   is always a usable login prompt.
2. `greetd.vt = 1` only. Ctrl+Alt+F2 remains a plain getty.
3. The change is validated with `nixos-rebuild test` before any `switch`, so a
   reboot reverts a broken greeter.

## Verification

- `nix flake check` evaluates.
- `greetd-proxy --mock` driven by hand from a shell: the stdio protocol
  produces the expected `auth_message` / `success` / `auth_error` sequences.
- `greetd-proxy --theme` prints `dark` after sunset and `light` after sunrise,
  checked against `darkman get` in a running session.
- `quickshell -p modules/qml/GreeterDark.qml` and `GreeterLight.qml` under
  `--mock` in the running session: layout, selection treatment, focus
  treatment, and the full keyboard flow including a failed password.
- The lockscreens still work unchanged after the component move: lock with
  Mod+Shift+Escape in both darkman modes.
- `nixos-rebuild test`, then reboot into the real greeter and log in.
