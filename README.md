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

`flake.nix` is inputs plus one line — [`import-tree`](https://github.com/vic/import-tree) imports every `.nix` under `modules/`, and each file registers what it provides. Nothing is selected by an imports list: every feature is imported into every host and gated behind an `ogama.<domain>.<feature>.enable` option, so **what a machine runs is its `_toggles.nix`**. A module nobody enables still gets evaluated, which is what stops one rotting unnoticed.

- `modules/`: everything the module system sees
  - `features/{core,system,desktop,dev,server}/`: the building blocks, one file per concern — and one file holds *both* the NixOS and the Home Manager half where a concern has two
  - `hosts/<host>/`: `default.nix` (the only flake-parts module there, which builds that host's configurations), `_toggles.nix` (what this host runs), and `_`-prefixed entry modules and machine-specific extras
  - `flake/`: the plumbing — option declarations, package sets, and the aggregator that imports every feature
- `lib/`: not modules — plain functions and data (the colour palette, the QML theme substitution, the swayfx package, the storage roots)
- `qml/`: the greeter's QML, which is rendered by a NixOS module rather than a Home Manager one because the greeter user cannot read `/home`

A name starting with `_` is skipped by `import-tree`: that is how a file under `modules/` says "I am not a flake-parts module".

To change what a machine runs, edit `modules/hosts/<host>/_toggles.nix`. To add something reusable, add one file under `modules/features/<domain>/`.
- `docs/`: runbooks for the parts that bite (see below), plus `superpowers/` design specs and plans, one topic per dated file
- `tests/`: render fixtures for the laser bar — there is no unit-test framework, so the bar is verified by screenshotting it
- `pkgs/`: standalone package derivations exposed as flake outputs
- `templates/`: `nix flake init` templates for quick project scaffolding
- `sops/`: encrypted secrets committed to the repo (via [sops-nix](https://github.com/Mic92/sops-nix))
- `secrets/`: gitignored, expected to exist locally but empty in a fresh checkout
- `assets/`, `scripts/`: images used by the config, and standalone shell/fish/python utility scripts

## Switching

Each target below runs on the machine it switches (no remote `--target-host`):
```
make personal     # NixOS + Home Manager switch (main desktop)
make oserv        # NixOS + Home Manager switch (home server)
make epita        # Home Manager switch (EPITA computer)
make epita-light  # Home Manager switch (EPITA computer, trimmed down)
make check        # nix flake check
make update       # nix flake update
```

These wrap [`nh`](https://github.com/nix-community/nh) (`nh os switch`/`nh home switch`),
which every profile installs via `programs.nh`. Without `make`, the raw
equivalents are:
```
nh os switch . -H personal
nh os switch . -H oserv
nh home switch . -c <profile>   # epita, epita-light
```

## Desktop shell

The `personal` profile's Sway session runs [Quickshell](https://quickshell.org)
(`modules/features/desktop/laserbar/`) instead of a traditional bar:

- the **laser bar** — a top bar drawn as two beams that collide at a point
  driven by battery charge, carrying workspace, wifi, clock and media modules;
- a **control panel** that slides out of it — toggles, audio, disks, oserv
  metrics, weather, calendar, and a notification centre (Quickshell is the
  notification server; KDE Connect relays arrive grouped by real sender);
- an **oserv status widget** reading the server's Gatus and Prometheus APIs;
- the **lockscreen**, a different design per variant rather than one recoloured
  skin.

Each widget is its own file under `components/`. Colours come from one palette
file and are rendered into a dark tree and a light tree that `darkman` swaps at
sunrise and sunset — there is no Stylix any more. See `docs/theming.md`.

To add a widget or a panel zone, read `docs/adding-a-bar-widget.md` first: it
records the performance rules that are already scar tissue, and the headless
render harness that stands in for a test suite.

## Documentation

The parts with non-obvious failure modes have runbooks:

| Doc | Read it before |
|---|---|
| `docs/theming.md` | changing any colour, or adding an app to the dark/light switch |
| `docs/adding-a-bar-widget.md` | touching the laser bar or its control panel |
| `docs/adding-a-server-service.md` | putting a new service on `oserv` |
| `docs/calendar-stack.md` | touching RustiCal, `calendar_syncer` or Calino |
| `docs/greeter.md` | touching greetd, the greeter QML or the login path |
| `docs/status-widget.md` | touching the oserv status widget or its APIs |

## Templates

```
nix flake init --template github:Ogama-0/nixos-configuration#<template>
```

Available: `python`, `c`, `epita-c` (EPITA-style C practical), `asm68k`.

## Packages

```
nix shell github:Ogama-0/nixos-configuration#<pkg>
```

Available:

- `librepods` — [kavishdevar's package](https://github.com/kavishdevar/librepods)
- `calino` — [Ivan-Malinovski's web CalDAV client](https://github.com/Ivan-Malinovski/calino), built for this server's own hostname
- `greetd-proxy` — the greeter's bridge to greetd's socket (see `docs/greeter.md`)
- `corpta-font`, `orbitron-font` — display faces used by the bar and greeter

The server also self-hosts its calendars — RustiCal (CalDAV), `calendar_syncer`
and Calino. See `docs/calendar-stack.md` for the setup that cannot be
declared in Nix (app tokens, DNS, the sops key).

## Known issues

**Greeter login is improved but not fully fixed.** Logging in used to show a
spurious "wrong password", stall for several seconds, then flash a TTY before
Sway started. Three real bugs behind that are fixed (see `docs/greeter.md`):

- a held or double-tapped Enter on the username field submitted an *empty*
  password, which PAM rejected and then punished with its fail delay;
- the `agreety` fallback fired on **every** login, because greetd kills the
  greeter on success so a successful login also exits non-zero;
- the password field went disabled during PAM's fail delay and silently ate
  anything typed into it, turning one mistype into two rejections.

The TTY flash is gone and logins are much cleaner, but it has not yet been
confirmed that the first-login rejection is gone for good. While that stays
open, `debugTrace = true` in `modules/features/desktop/greeter.nix` writes
`/tmp/greeter-trace.log` (message types, timings and password *lengths* -
never a password) and `/tmp/greeter-quickshell.log`. Set it to `false` and
rebuild to turn both off.

## TODO

### personal
- add a TTY login menu []
- manage sway idle &co issue : media player
- quickshell widget graphana status server

### server
- build a website for ogama.me
- qbtorrent : let qbittorent add file in jellyfin/film and jellyfin/audiobook
- build the hdd architectur with 2 2tb hdd with backup on the 4to hdd
- use kristen's vps to let people access to my server (throught tailescale tunel)
- FIX : joplin filling the routeur
