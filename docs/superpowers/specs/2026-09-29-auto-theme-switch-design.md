# Automatic dark/light theme switching at sunset/sunrise

## Goal

Automatically switch the desktop between the existing dark theme
(`horizon-dark.yaml`) and a new light counterpart (`horizon-light.yaml`) at
local sunset and sunrise, on the `personal` profile, without a full
`home-manager switch` rebuild at each transition.

## Background

Audited in this session: stylix currently drives most desktop theming from a
single hardcoded `base16Scheme` / `polarity = "dark"` in
`modules/home-manager/stylix.nix`. With one exception (gtk's dconf
`color-scheme` key, which is genuinely runtime-mutable), everything stylix
themes — waybar CSS, tofi colors, quickshell QML color tokens, mako/swaync
styling — is generated once as a static file at Nix build/activation time.
There is currently no light-mode scheme wired up anywhere in the repo; the
only "light" artifact is a hand-authored `LockLight.qml` that doesn't read
stylix colors at all.

Flipping `stylix.polarity` and re-running `home-manager switch` would
correctly re-theme everything stylix covers, but costs a rebuild (tens of
seconds) and restarts of waybar/quickshell/etc. twice a day, which is
disruptive for something that should be instant.

Reference implementation surveyed: `Pixilie/nix-configuration` uses
`services.darkman` (packaged in nixpkgs, has a home-manager module) purely as
a runtime trigger — its dark/light-mode scripts symlink-swap a pre-baked
color/asset variant into place and send the owning app a reload signal
(SIGUSR2 to waybar, `makoctl mode`, dconf writes), with no rebuild involved.
That repo hand-authors both color variants per app rather than deriving them
from a theming framework. This design adopts darkman's runtime-switch
mechanism but keeps this repo's existing single-source-of-truth model: both
variants are derived from the two base16 scheme YAML files, not hand-copied
hex.

## Non-goals

- Firefox / zen-browser: stays statically themed via the existing
  `stylix.targets.firefox` / `stylix.targets.zen-browser` build-time
  integration. No live switch, no restart-on-theme-change.
- `oserv` / `epita` / `epita-light` profiles: out of scope — this is a
  desktop (`personal`) concern only.
- Wallpaper: stays whatever `stylix.image` currently sets. No dark/light
  wallpaper pair, no `swaymsg` background switching.
- Quickshell bar/widget shell (`shell.qml`, `Wallpaper.qml`, `Clock.qml`,
  `Music.qml`, `Calendar.qml`, `RevealMask.qml`, `LaserBar.qml`): still
  under active development by the user — out of scope, not touched, not
  restarted. Only the quickshell lockscreen (`Lock.qml`) is switched.
- Changing the default build-time theme: `modules/home-manager/stylix.nix`
  keeps producing the dark theme by default on a fresh
  `nixos-rebuild switch` / `home-manager switch`. darkman only adjusts the
  runtime-mutable pieces below, after activation.

## Design

### 1. Sun-time source

`services.darkman` (new `modules/home-manager/darkman.nix`) computes
sunset/sunrise itself from a `lat`/`lng` pair (`usegeoclue = false`, explicit
coordinates — no location-service dependency).

Coordinates track `time.timeZone` automatically rather than being
hand-entered or duplicated in a second config location. Home-manager is
built standalone in this flake (not wired as a NixOS module), so it has no
`osConfig` access to read `time.timeZone` at eval time — so the sync happens
at activation instead: a home-manager activation script reads `/etc/timezone`
(the file NixOS writes from `time.timeZone` on every `nixos-rebuild switch`),
looks it up in a small static lookup table, and (re)writes the resolved
`lat`/`lng` into darkman's `~/.config/darkman/config.yaml`, overriding the
module's static default. The lookup table:

```nix
{
  "Europe/Paris" = { lat = 48.8566; lng = 2.3522; };
  "America/Monterrey" = { lat = 25.6866; lng = -100.3161; };
  "America/Mazatlan" = { lat = 23.2494; lng = -106.4111; };
}
```

(covers `host/personal/configuration.nix`'s current `time.timeZone` value
plus its two commented-out travel alternates). Practically: changing
`time.timeZone` in the NixOS config, then running `nixos-rebuild switch`
followed by `home-manager switch`, is enough to re-sync — no second field to
remember to update.

If `/etc/timezone`'s value isn't in the lookup table, fall back to Paris
coordinates and note it as a known gap (not worth a more general geocoding
dependency for a personal config).

### 2. Color source

Both `${pkgs.base16-schemes}/share/themes/horizon-dark.yaml` and
`horizon-light.yaml` (confirmed present in nixpkgs) are parsed into base16
color attrsets at eval time, independent of the global `stylix.polarity`
switch. Implementation will use whatever stylix exposes for parsing a scheme
file standalone (equivalent to what `config.lib.stylix.colors` does
internally for the active polarity) — exact helper to confirm during
implementation; worst case, a short local YAML-parsing shim
(`pkgs.formats.yaml` reader is sufficient since base16 scheme files are
plain YAML).

These two color sets become the single source of truth for every dual-baked
target below — no hand-copied hex.

### 3. Per-target switching strategy

| Target | Mechanism | Notes |
|---|---|---|
| gtk | `dconf write /org/gnome/desktop/interface/color-scheme` | Already reads `stylix.polarity` at build via `modules/home-manager/display/gtk.nix`; darkman writes the same key directly at runtime, no rebuild needed. |
| waybar | Dual-baked `colors-dark.css` / `colors-light.css`; symlink the active one to the CSS import target; `pkill -x -SIGUSR2 waybar` to reload | Mirrors `modules/home-manager/display/hyprland/waybar.nix`'s existing (currently commented-out) style hookup. |
| mako | Dual-baked `mode=dark` / `mode=light` sections in `modules/home-manager/display/sway/mako.nix`; switch via `makoctl mode -a <mode> -r <other>` | mako supports named modes natively; no file swap needed. |
| swaync | Dual-baked CSS; symlink swap + `swaync-client --reload-css` | |
| tofi | Dual-baked colors file; symlink swap only | tofi launches fresh per invocation (app launcher), so no reload signal is needed — next launch just picks up the new symlink target. |
| quickshell lockscreen only | Dual-baked color tokens substituted into `Lock-dark.qml`/`Lock-light.qml`; plain symlink swap of `components/Lock.qml`, no daemon restart | Bar/widget shell excluded (active development, see Non-goals). Assumes quickshell loads `Lock.qml` fresh per lock invocation rather than caching it — if that assumption is wrong, live verification will surface it as a known limitation rather than adding an in-scope daemon restart. |

### 4. darkman wiring

`modules/home-manager/darkman.nix` enables `services.darkman`, sets
`settings.lat`/`settings.lng` from the lookup above, and defines
`darkModeScripts` / `lightModeScripts` (one entry per target row above,
following the pattern in Pixilie's `darkman.nix` reference). Imported from
`host/personal/home.nix` only.

### 5. Testing

- `nix flake check` after wiring.
- A real `home-manager switch --flake .#personal` to confirm normal build
  still produces the (unchanged) default dark theme and doesn't regress
  anything audited above.
- Manual verification of each darkman script: `darkman set dark` /
  `darkman set light` (or equivalent CLI toggle) and visually confirm
  waybar, mako, swaync, tofi, quickshell lockscreen, and gtk apps all
  flip, without restarting the sway session.
- Confirm actual sunset/sunrise-triggered transition once, or trust
  darkman's own scheduling (it's a mature, focused tool) after the manual
  toggle test passes.

## Open questions for implementation planning

- Exact stylix-internal (or standalone) function to parse a base16 YAML
  scheme file into colors without going through the global `polarity`
  switch.
- Resolved during implementation: quickshell scope was narrowed to the
  lockscreen only (bar/widget shell excluded, under active development),
  and the lockscreen switch uses a plain symlink swap with no daemon
  restart or IPC call, assuming `Lock.qml` loads fresh per lock invocation.
- Whether swaync is even themed via stylix today (audit found no explicit
  `stylix.targets.swaync` call, relying on `autoEnable`) — confirm before
  writing its dual-bake.
