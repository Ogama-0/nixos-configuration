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
nix flake init --template github:/ogama-0/nixos-configuration#<template>
```
Templates: `python`, `c`, `epita-c`, `asm68k`.

There is no linter/formatter/test suite wired into this repo — validate changes with `nix flake check` and, when touching a specific profile, a real `switch` run.

## Architecture

**Entry point (`flake.nix`)** wires everything together: it imports `host/profiles.nix` for per-user config data, then defines `nixosConfigurations.{personal,oserv}` and `homeConfigurations.{personal,oserv,epita,epita-light}`. Every configuration receives a `cfg` value (the profile record from `host/profiles.nix`) via `specialArgs`/`extraSpecialArgs`, and `pkgs`/`lpkgs`/`upkgs` (local packages from `pkgs/`, and flake-input packages like `zen-browser`) via the same mechanism — modules pull these out of their function arguments (`{ cfg, pkgs, ... }:`) rather than hardcoding values.

**`host/profiles.nix`** is the single source of per-user truth: username, home directory, mail, SSH pubkey, server domain, and profile-specific extras (e.g. server storage paths under `SSD`/`HDD`/`BACKUP`, or the `epita` login name). `mkProfile` builds a base record and merges in an `extra` function's output. `cfg-perso` embeds `cfg-server` under `.server` so the personal profile can reference server paths (e.g. for backups/shares). Changing a username, path, or key happens here, not in the individual host files.

**`host/<profile>/`** holds the actual NixOS (`configuration.nix`) and Home Manager (`home.nix` / `<profile>.nix`) entry modules for that host, plus `hardware-configuration.nix` and a `nixosconf/`/`home-manager/` subfolder for config that's genuinely specific to that one machine (e.g. `host/serveur/nixosconf/backup-server.nix`, `host/personal/nixosconf/backup-laptop.nix`). Each entry module is mostly an `imports` list pulling in shared modules plus a handful of host-only settings (hostname, firewall, boot loader, `stateVersion`).

**`modules/nixosconf/`** and **`modules/home-manager/`** are the shared, reusable building blocks — one file (or subfolder with `default.nix`) per concern (`tailscale.nix`, `docker.nix`, `jellyfin.nix`, `stylix.nix`, `display/sway`, etc.). New reusable functionality should live here and get imported from the relevant `host/<profile>/*.nix` entry file(s) rather than being duplicated per host. Server-only services (`jellyfin.nix`, `immich.nix`, `nginx.nix`, `caddy.nix`, `headscale.nix`, ...) live alongside desktop-only ones (`display/*`, `firefox.nix`, `kitty.nix`, ...) in the same two directories — only the host's `imports` list determines what actually applies.

**`pkgs/`** contains standalone package derivations (`librepods.nix`) exposed as flake outputs under `packages.${system}`, consumed elsewhere via the `lpkgs` set built in `flake.nix`.

**`secrets/`** is gitignored and expected to exist locally but empty in the checkout — do not assume files there are present or commit anything into it.

**`templates/`** holds `nix flake init` templates (registered in `templates/default.nix`), unrelated to the host configs — self-contained flakes for quick project scaffolding (C, Python, asm68k, EPITA-style C practicals).

**`scripts/`** is plain shell/fish/python utility scripts (bluetooth/wifi/power toggles for `swaync`, wireguard toggles for fish, backup/mount helpers) invoked from Home Manager/NixOS modules or manually — not part of the Nix build graph itself.
