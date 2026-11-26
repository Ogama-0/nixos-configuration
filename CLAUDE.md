# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal NixOS + Home Manager flake configuration for four profiles: `personal` (main desktop, ASUS ZenBook 14 OLED UX3405CA), `personal-lenovo` (the previous main desktop, kept running but no longer actively backed up), `oserv` (home server, hostname `oserv`, domain `ogama.me`), and `epita` / `epita-light` (school computer, home-manager only, faster-building variant). Also vends reusable `nix flake init` templates and a couple of standalone packages.

## Commands

A `Makefile` at the repo root wraps the switches below in `make personal`,
`make personal-lenovo`, `make oserv`, `make epita`, `make epita-light`, `make check`, `make update`.
Each target runs on the machine it switches (no remote `--target-host`).

Switch a NixOS host (from the machine being configured), via
[`nh`](https://github.com/nix-community/nh) (every profile installs it
through `programs.nh`, see `modules/features/core/nh.nix` and
`modules/features/core/nh.nix`):
```
nh os switch . -H personal
nh os switch . -H personal-lenovo
nh os switch . -H oserv
```

Switch a Home Manager profile — **always standalone, on every profile**:
```
nh home switch . -c <profile>
```
Valid `<profile>` values: `personal`, `personal-lenovo`, `oserv`, `epita`, `epita-light`.

`modules/hosts/personal/_hardware-configuration.nix` is a placeholder (see
its header comment) until it's overwritten with real `nixos-generate-config`
output from the ZenBook — that's the one file a fresh clone onto that machine
needs replaced before `make personal` builds for real.

**The NixOS switch does not carry Home Manager with it.** `personal` and `oserv`
build their home side with `inputs.home-manager.lib.homeManagerConfiguration`
(see `modules/hosts/personal/default.nix`), not with
`home-manager.nixosModules.home-manager`, so the two are independent
derivations with independent activations. `make personal` runs only
`nh os switch`; the home half needs `make personal-hm` as a second command.
A change to a feature's home side will silently not take effect until you run
it — the NixOS switch succeeds and reports no error, because nothing in the
system closure ever referenced that module.

To change what a machine runs, edit `modules/hosts/<host>/_toggles.nix`. To add something reusable, add one file under `modules/features/<domain>/`.

Check the flake evaluates without switching:
```
nix flake check
```

Build a package defined in `pkgs/`:
```
nix build .#librepods
```

Use a project template:
```
nix flake init --template github:Ogama-0/nixos-configuration#<template>
```
Templates: `python`, `c`, `epita-c`, `asm68k`.

There is no test suite wired into this repo. Validate with `nix flake check` and, when touching a specific profile, a real `switch` run.

**Run `nixfmt` on every `.nix` file you touch before committing.** It's the formatter Helix is configured to auto-format with (`modules/features/dev/helix.nix`), so an unformatted file is a diff against what the user's own editor would produce on save:
```
nixfmt <file>...
```

**`nix flake check` is weaker than it looks.** It only shallow-checks `homeConfigurations`, so it never forces the generated `xdg.configFile` *text* — which is exactly where the `@token@` substitution that themes every QML file happens. A green check is compatible with QML that does not evaluate. Force the real thing:

```
nix eval --raw .#homeConfigurations.<profile>.activationPackage.drvPath
```

And stage before you believe any result: flakes copy only tracked files into the store, so an un-`git add`ed `.nix` file is simply absent from the evaluation and the check passes against the tree without it. Add files by name — this tree habitually holds unrelated in-progress work, so `git add -A` sweeps in more than you meant.

Every module in the tree is reachable from `flake.nix` and evaluated on every check, including the unfinished ones: `modules/features/desktop/hyprland/` and `modules/features/server/headscale.nix` are imported with their flags off. Evaluating while disabled is weaker than working — enabling hyprland today still hits a `home.pointerCursor.name` conflict with `modules/hosts/personal/_home.nix` — but they can no longer rot silently.

## Architecture

**Entry point (`flake.nix`)** is inputs plus `flake-parts.lib.mkFlake` with a single `imports = [ (import-tree ./modules) ]`. It wires nothing: every `.nix` under `modules/` is imported automatically and registers what it provides. Adding a module is adding a file.

**Nothing is selected by an imports list.** Every feature is imported into every host of its kind by `modules/flake/aggregate.nix`, and each one gates its body on an `ogama.<domain>.<feature>.enable` option. What a machine runs is its `_toggles.nix`, not which files it imports. A module nobody enables still evaluates, which is what stops one rotting unnoticed.

**`modules/flake/`** is the plumbing: `options.nix` declares `featureModules.{nixos,home}` plus the Home Manager outputs flake-parts does not know about; `pkg-sets.nix` builds `pkgs`/`upkgs`/`localPackages` once and hands them round via `_module.args`; `aggregate.nix` is the two-line module that imports every feature; `packages.nix` and `templates.nix` expose the corresponding outputs.

**`modules/features/{core,system,desktop,dev,server}/`** are the building blocks, one file per concern — and one file holds *both* sides of a concern where it has two (`nh`, `wakapi`). Each declares its options once and registers that declaration to both the NixOS and the Home Manager side, so a host's `_toggles.nix` can set a flag regardless of which side implements it. See `docs/superpowers/specs/2026-11-13-example-service-module.nix` for the shape.

**`modules/hosts/<host>/`** holds `default.nix` — the only flake-parts module in the directory, which calls `nixosSystem`/`homeManagerConfiguration` — plus `_toggles.nix` (what this host runs) and `_`-prefixed entry modules and host-private config. `epita` and `epita-light` share one entry module and differ only in which toggles file they are handed.

**The `_` prefix is load-bearing.** `import-tree` imports every `.nix` under `modules/` and skips any path whose basename starts with `_`. Anything there that is not a flake-parts module — a host's toggles, a host-private NixOS module, a sub-module of a gated feature — must be `_`-prefixed. A sub-module of a gated feature also carries its own `mkIf`: the import that pulls it in cannot be conditional.

**Per-host data is declared options**, not an attrset: `ogama.identity.*`, `ogama.server.{domain,paths,path}` in `modules/features/core/shared-options.nix`, registered on both sides and set by the host they describe. `ogama.server.path` is a read-only tree derived from three root options — `ogama.server.paths.{ssd,hdd,backup}`, defaulting to `/mnt/ssd`, `/mnt/hdd` and `/mnt/backup` from `lib/constants.nix`. Change a storage root there, not at the thirty-odd leaves that hang off it.

**oserv runs ZFS** (`ogama.system.zfs.enable`), which is why it pins `boot.kernelPackages = pkgs.linuxPackages` — the ZFS kernel module does not build against `linuxPackages_latest` on this nixpkgs pin. The same LTS constraint independently applies to `personal-lenovo` through `nvidia-open`; `personal` has no Nvidia GPU and carries no such pin.

**`lib/`** is not modules. It is plain functions and data `import`ed directly: the colour palette (`palette.nix`, the single source for every colour on the desktop), the QML `@token@` substitution (`qml-theme.nix`), per-app theme renderers, the `swayfx` package both sway and greetd need by absolute store path, and `constants.nix` (the domain and storage roots, needed by `packages.calino` before any module exists). **`qml/`** is every line of QML in the repo - the whole quickshell desktop, not just the greeter - organised one directory per feature (see below). Both sit at the repo root, outside the import root.

**The `qml/` tree is one directory per feature**, and that layout is load-bearing twice over. `modules/features/desktop/laserbar/default.nix` *walks* it — every `.qml` under `qml/` is installed into both themed trees at the same relative path, so adding a component is adding a file and there is no list to forget. And the installed layout mirrors the source layout exactly, so a `nix eval` of a generated path reads the same as the file you edited.

```
qml/shell.qml                 the session root: instantiates one of everything
qml/common/                   used by two or more features - PanelBeam, PanelIcon,
                              PanelSheet, ColorUtils, RevealMask, Sparkline,
                              CalendarModel, RemoteBadge, and the session-wide
                              models shell.qml owns (MprisModel, RemoteSpectrum,
                              WeatherModel)
qml/laserbar/                 the momentary bar and its widgets
qml/desktopwidgets/           the always-on desktop surfaces: wallpaper, clock,
                              music card, calendar card, server status
qml/lockscreen/               LockDark/LockLight - two designs, one Lock.qml
qml/notification/             the freedesktop notification server, the centre
                              and the toasts
qml/panel/mainpanel/          ControlPanel and its zones
qml/panel/messagepanel/       the KDE Connect SMS surface
qml/greeter/                  the greetd surfaces - NOT part of the walk
```

**Directory names must be legal QML module names**, which means no hyphens: quickshell's scanner rejects `desktop-widget` with `Module path contains invalid characters` and the directory stops resolving as an import. That is why the bucket is `desktopwidgets`.

**A component used from another bucket needs an explicit `import`.** A directory import covers one directory and no other — not its subdirectories — and a missing one fails as `X is not a type`, which reads like a typo rather than a missing import. `qml/panel/mainpanel/ControlPanel.qml` is the worked example: it imports `"../../common"`, `"../../notification"` and `"../messagepanel"`, and needs no import at all for the zones sitting beside it.

**Two things are deliberately outside the walk.** `qml/greeter/` is installed to `/etc/greeter` by `modules/features/desktop/greeter.nix`, because the greetd user cannot read `/home` — it shares the palette with the desktop and nothing else. And `qml/lockscreen/Lock{Dark,Light}.qml` are two deliberately different designs behind *one* installed `lockscreen/Lock.qml`: `shell.qml` instantiates `Lock`, and which design that is comes from the variant.

**`pkgs/`** contains standalone package derivations (`librepods.nix`) exposed as flake outputs under `packages.${system}`, consumed elsewhere via the `lpkgs` set built in `flake.nix`.

**`secrets/`** is gitignored and expected to exist locally but empty in the checkout — do not assume files there are present or commit anything into it.

**`templates/`** holds `nix flake init` templates (registered in `templates/default.nix`), unrelated to the host configs — self-contained flakes for quick project scaffolding (C, Python, asm68k, EPITA-style C practicals).

**`scripts/`** is plain shell/fish/python utility scripts (bluetooth/wifi/power toggles for `swaync`, the laser bar's CPU/gating/preview/probe helpers, rofi themes) invoked from Home Manager/NixOS modules or manually — not part of the Nix build graph itself. **`tests/laserbar/`** is render fixtures, not a test framework: each is a QML scene screenshotted headlessly by `scripts/laserbar-preview.sh` and asserted on with `scripts/laserbar-probe.sh`.

**`docs/`** is prose, not config. Three runbooks matter before writing code:

- `docs/adding-a-server-service.md` for putting a new service on `oserv` — module layout, Caddy/DNS/port conventions, the Gatus and process-exporter wiring every service is expected to register with, and the non-obvious failure modes (the `*.tail` names are individual CNAMEs managed outside this repo, `comm` matchers silently match nothing when truncated).
- `docs/adding-a-bar-widget.md` for putting something new on the sway laser bar (a DND toggle, a battery readout) — the group/widget split, the properties the bar binds for you, the performance rules that are already scar tissue, and the headless render harness that stands in for a test suite.
- `docs/theming.md` before changing any colour or adding an app to the dark/light switch — the one-palette rule, and the constraint that explains most of the code: anything `darkman` rewrites at runtime must *not* be managed by `xdg.configFile`, or it becomes a read-only store symlink darkman cannot replace.

`docs/calendar-stack.md`, `docs/greeter.md`, `docs/status-widget.md` and `docs/messages-panel.md` cover those four subsystems' own setup and gotchas. The last of those is also where the KDE Connect SMS surface is written down (with `docs/kdeconnect-sms-payload.md`), and it is the only part of the panel that takes keyboard focus - read its focus section before touching `modes.panel`. `docs/superpowers/{specs,plans}/` holds per-feature design specs and implementation plans, dated and one topic per file.
