# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal NixOS + Home Manager flake configuration for three profiles: `personal` (main desktop), `oserv` (home server, hostname `oserv`, domain `ogama.me`), and `epita` / `epita-light` (school computer, home-manager only, faster-building variant). Also vends reusable `nix flake init` templates and a couple of standalone packages.

## Commands

Switch a NixOS host (from the machine being configured):
```
sudo nixos-rebuild switch --flake .#personal
sudo nixos-rebuild switch --flake .#oserv
```

Switch a Home Manager profile (used standalone for `epita`/`epita-light`, and as part of the NixOS switch for `personal`/`oserv`):
```
nix run nixpkgs#home-manager -- switch --flake .#<profile>
```
Valid `<profile>` values: `personal`, `oserv`, `epita`, `epita-light`.

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

Two trees are **not** reachable from `flake.nix` and therefore never checked by anything: `modules/home-manager/display/hyprland/` (commented out of `host/personal/home.nix`) and `modules/nixosconf/headscale.nix`. Both are kept on purpose as unfinished projects. Assume they are stale until evaluated.

## Architecture

**Entry point (`flake.nix`)** wires everything together: it imports `host/profiles.nix` for per-user config data, then defines `nixosConfigurations.{personal,oserv}` and `homeConfigurations.{personal,oserv,epita,epita-light}`. Every configuration receives a `cfg` value (the profile record from `host/profiles.nix`) via `specialArgs`/`extraSpecialArgs`, and `pkgs`/`lpkgs`/`upkgs` (local packages from `pkgs/`, and flake-input packages like `zen-browser`) via the same mechanism — modules pull these out of their function arguments (`{ cfg, pkgs, ... }:`) rather than hardcoding values.

**`host/profiles.nix`** is the single source of per-user truth: username, home directory, mail, SSH pubkey, server domain, and profile-specific extras (e.g. server storage paths under `SSD`/`HDD`/`BACKUP`, or the `epita` login name). `mkProfile` builds a base record and merges in an `extra` function's output. `cfg-perso` embeds `cfg-server` under `.server` so the personal profile can reference server paths (e.g. for backups/shares). Changing a username, path, or key happens here, not in the individual host files.

**`host/<profile>/`** holds the actual NixOS (`configuration.nix`) and Home Manager (`home.nix` / `<profile>.nix`) entry modules for that host, plus `hardware-configuration.nix` and a `nixosconf/`/`home-manager/` subfolder for config that's genuinely specific to that one machine (e.g. `host/serveur/nixosconf/backup-server.nix`, `host/personal/nixosconf/backup-laptop.nix`). Each entry module is mostly an `imports` list pulling in shared modules plus a handful of host-only settings (hostname, firewall, boot loader, `stateVersion`).

**`modules/nixosconf/`** and **`modules/home-manager/`** are the shared, reusable building blocks — one file (or subfolder with `default.nix`) per concern (`tailscale.nix`, `docker.nix`, `jellyfin.nix`, `darkman.nix`, `display/sway`, etc.). New reusable functionality should live here and get imported from the relevant `host/<profile>/*.nix` entry file(s) rather than being duplicated per host. Server-only services (`jellyfin.nix`, `immich.nix`, `caddy.nix`, `rustical.nix`, ...) live alongside desktop-only ones (`display/*`, `firefox.nix`, `kitty.nix`, ...) in the same two directories — only the host's `imports` list determines what actually applies.

**`modules/lib/`** is not modules. It is plain functions and data `import`ed directly by modules: the colour palette (`palette.nix`, the single source for every colour on the desktop), the QML `@token@` substitution (`qml-theme.nix`), per-app theme renderers, and the `swayfx` package both sway and greetd need by absolute store path. **`modules/qml/`** holds the greeter's QML, rendered by a NixOS module rather than a Home Manager one because the greeter user cannot read `/home`.

**`pkgs/`** contains standalone package derivations (`librepods.nix`) exposed as flake outputs under `packages.${system}`, consumed elsewhere via the `lpkgs` set built in `flake.nix`.

**`secrets/`** is gitignored and expected to exist locally but empty in the checkout — do not assume files there are present or commit anything into it.

**`templates/`** holds `nix flake init` templates (registered in `templates/default.nix`), unrelated to the host configs — self-contained flakes for quick project scaffolding (C, Python, asm68k, EPITA-style C practicals).

**`scripts/`** is plain shell/fish/python utility scripts (bluetooth/wifi/power toggles for `swaync`, the laser bar's CPU/gating/preview/probe helpers, rofi themes) invoked from Home Manager/NixOS modules or manually — not part of the Nix build graph itself. **`tests/laserbar/`** is render fixtures, not a test framework: each is a QML scene screenshotted headlessly by `scripts/laserbar-preview.sh` and asserted on with `scripts/laserbar-probe.sh`.

**`docs/`** is prose, not config. Three runbooks matter before writing code:

- `docs/adding-a-server-service.md` for putting a new service on `oserv` — module layout, Caddy/DNS/port conventions, the Gatus and process-exporter wiring every service is expected to register with, and the non-obvious failure modes (the `*.tail` names are individual CNAMEs managed outside this repo, `comm` matchers silently match nothing when truncated).
- `docs/adding-a-bar-widget.md` for putting something new on the sway laser bar (a DND toggle, a battery readout) — the group/widget split, the properties the bar binds for you, the performance rules that are already scar tissue, and the headless render harness that stands in for a test suite.
- `docs/theming.md` before changing any colour or adding an app to the dark/light switch — the one-palette rule, and the constraint that explains most of the code: anything `darkman` rewrites at runtime must *not* be managed by `xdg.configFile`, or it becomes a read-only store symlink darkman cannot replace.

`docs/calendar-stack.md`, `docs/greeter.md` and `docs/status-widget.md` cover those three subsystems' own setup and gotchas. `docs/superpowers/{specs,plans}/` holds per-feature design specs and implementation plans, dated and one topic per file.
