# NixOS configuration

My personal NixOS + Home Manager flake, covering a main desktop, a home server, and a school laptop.

## Profiles

| Profile | What it is |
|---|---|
| `personal` | Main desktop (NixOS + Home Manager, Sway) |
| `oserv` | Home server, hostname `oserv`, domain `ogama.me` (NixOS + Home Manager) |
| `epita` | School computer (Home Manager only) |
| `epita-light` | Same as `epita`, trimmed down to build faster |

## Structure

- `host/`: per-profile entry points
  - `profiles.nix`: single source of truth for usernames, paths, SSH keys, and other per-profile data
  - `<profile>/`: `configuration.nix` (NixOS) and `home.nix`/`<profile>.nix` (Home Manager) for that machine, plus `hardware-configuration.nix` and any machine-specific extras
- `modules/`: reusable building blocks, one file (or folder) per concern
  - `home-manager/`: user-level config (shell, editors, `display/` for window managers, etc.)
  - `nixosconf/`: system-level config (services, networking, etc.)
- `pkgs/`: standalone package derivations exposed as flake outputs
- `templates/`: `nix flake init` templates for quick project scaffolding
- `sops/`: encrypted secrets committed to the repo (via [sops-nix](https://github.com/Mic92/sops-nix))
- `secrets/`: gitignored, expected to exist locally but empty in a fresh checkout
- `assets/`, `scripts/`: images used by the config, and standalone shell/fish/python utility scripts

## Switching

Switch a NixOS host (from the machine being configured):
```
sudo nixos-rebuild switch --flake .#personal
sudo nixos-rebuild switch --flake .#oserv
```

Switch a Home Manager profile (standalone for `epita`/`epita-light`; already part of the NixOS switch above for `personal`/`oserv`):
```
nix run nixpkgs#home-manager -- switch --flake .#<profile>
```

Check the flake evaluates without switching:
```
nix flake check
```

## Desktop widgets

The `personal` profile's Sway session runs a small [Quickshell](https://quickshell.org) setup (`modules/home-manager/display/sway/quickshell/`) instead of a traditional bar: a floating clock/weather card, a media-player card (MPRIS + PipeWire controls, a `cava`-driven equalizer ring, real album art), and a read-only calendar card (month grid + next events, synced from a Proton Calendar share link via `vdirsyncer`/`khal`). Each widget is its own file under `components/`, themed from the active Stylix color scheme.

## Templates

```
nix flake init --template github:Ogama-0/nixos-configuration#<template>
```

Available: `python`, `c`, `epita-c` (EPITA-style C practical), `asm68k`.

## Packages

```
nix shell github:Ogama-0/nixos-configuration#<pkg>
```

Available: `librepods` ([kavishdevar's package](https://github.com/kavishdevar/librepods))

## TODO

### personal
- add a TTY login menu
- switch background every X seconds, or when switching workspace
- make the Sway config lighter, Hyprland config stronger

### server
- build a website for ogama.me
- build an internal API tying together qBittorrent, Jellyfin, and a web UI
