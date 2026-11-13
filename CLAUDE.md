# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal NixOS + Home Manager flake configuration for three profiles: `personal` (main desktop), `oserv` (home server, hostname `oserv`, domain `ogama.me`), and `epita` / `epita-light` (school computer, home-manager only, faster-building variant). Also vends reusable `nix flake init` templates and a couple of standalone packages.

## Commands

A `Makefile` at the repo root wraps the switches below in `make personal`,
`make oserv`, `make epita`, `make epita-light`, `make check`, `make update`.
Each target runs on the machine it switches (no remote `--target-host`).

Switch a NixOS host (from the machine being configured), via
[`nh`](https://github.com/nix-community/nh) (every profile installs it
through `programs.nh`, see `modules/features/core/nh.nix` and
`modules/features/core/nh.nix`):
```
nh os switch . -H personal
nh os switch . -H oserv
```

Switch a Home Manager profile (used standalone for `epita`/`epita-light`, and as part of the NixOS switch for `personal`/`oserv`):
```
nh home switch . -c <profile>
```
Valid `<profile>` values: `personal`, `oserv`, `epita`, `epita-light`.

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

There is no linter/formatter/test suite wired into this repo. Validate with `nix flake check` and, when touching a specific profile, a real `switch` run.

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

**Per-host data is declared options**, not an attrset: `ogama.identity.*`, `ogama.server.{domain,paths,path}` in `modules/features/core/shared-options.nix`, registered on both sides and set by the host they describe. `ogama.server.path` is a read-only tree derived from three root options.

**`lib/`** is not modules. It is plain functions and data `import`ed directly: the colour palette (`palette.nix`, the single source for every colour on the desktop), the QML `@token@` substitution (`qml-theme.nix`), per-app theme renderers, the `swayfx` package both sway and greetd need by absolute store path, and `constants.nix` (the domain and storage roots, needed by `packages.calino` before any module exists). **`qml/`** holds the greeter's QML, rendered by a NixOS module rather than a Home Manager one because the greeter user cannot read `/home`. Both sit at the repo root, outside the import root.

**`pkgs/`** contains standalone package derivations (`librepods.nix`) exposed as flake outputs under `packages.${system}`, consumed elsewhere via the `lpkgs` set built in `flake.nix`.

**`secrets/`** is gitignored and expected to exist locally but empty in the checkout — do not assume files there are present or commit anything into it.

**`templates/`** holds `nix flake init` templates (registered in `templates/default.nix`), unrelated to the host configs — self-contained flakes for quick project scaffolding (C, Python, asm68k, EPITA-style C practicals).

**`scripts/`** is plain shell/fish/python utility scripts (bluetooth/wifi/power toggles for `swaync`, the laser bar's CPU/gating/preview/probe helpers, rofi themes) invoked from Home Manager/NixOS modules or manually — not part of the Nix build graph itself. **`tests/laserbar/`** is render fixtures, not a test framework: each is a QML scene screenshotted headlessly by `scripts/laserbar-preview.sh` and asserted on with `scripts/laserbar-probe.sh`.

**`docs/`** is prose, not config. Three runbooks matter before writing code:

- `docs/adding-a-server-service.md` for putting a new service on `oserv` — module layout, Caddy/DNS/port conventions, the Gatus and process-exporter wiring every service is expected to register with, and the non-obvious failure modes (the `*.tail` names are individual CNAMEs managed outside this repo, `comm` matchers silently match nothing when truncated).
- `docs/adding-a-bar-widget.md` for putting something new on the sway laser bar (a DND toggle, a battery readout) — the group/widget split, the properties the bar binds for you, the performance rules that are already scar tissue, and the headless render harness that stands in for a test suite.
- `docs/theming.md` before changing any colour or adding an app to the dark/light switch — the one-palette rule, and the constraint that explains most of the code: anything `darkman` rewrites at runtime must *not* be managed by `xdg.configFile`, or it becomes a read-only store symlink darkman cannot replace.

`docs/calendar-stack.md`, `docs/greeter.md`, `docs/status-widget.md` and `docs/messages-panel.md` cover those four subsystems' own setup and gotchas. The last of those is also where the KDE Connect SMS surface is written down (with `docs/kdeconnect-sms-payload.md`), and it is the only part of the panel that takes keyboard focus - read its focus section before touching `modes.panel`. `docs/superpowers/{specs,plans}/` holds per-feature design specs and implementation plans, dated and one topic per file.
