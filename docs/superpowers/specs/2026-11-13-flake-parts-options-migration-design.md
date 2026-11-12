# Migrating to flake-parts + import-tree with enable options

Design document — 2026-11-13

## Intent

Today the tree decides *what a machine runs* with per-host `imports` lists of
relative paths. `host/serveur/configuration.nix` imports 24 files by path;
`host/epita/epita_light.nix` is `epita.nix` minus five lines. Nothing in the
tree states that `joplin-server.nix` needs `docker.nix`, or that
`postgresql-collation.nix` must be imported anywhere `services.postgresql`
runs — those are comments in an imports list, enforced by memory.

The consequence that actually bites: a module that no host imports is never
evaluated. `modules/home-manager/display/hyprland/` and
`modules/nixosconf/headscale.nix` are unreachable from `flake.nix` and have
been rotting unchecked. `nix flake check` passes happily without them.

The target is the shape NixOS itself uses: **every module is always imported
and always evaluated; what a host runs is a set of `enable` flags.**
Co-dependent pieces collapse behind one switch instead of being assembled by
hand. Parked work lives in the tree, gated off, and still has to evaluate on
every check.

## Goals

- `flake.nix` holds inputs and nothing else: no host wiring, no `specialArgs`
  plumbing, no package list.
- Every `.nix` under the module root is imported automatically. Adding a file
  is adding a module.
- One concern, one file — including concerns that span NixOS and Home Manager
  (`nh`, `wakapi`, `gns3`, `calendar-sync` each exist twice today).
- A host is a short set of flags plus its genuinely machine-specific facts
  (hostname, hardware, boot, `stateVersion`).
- Per-host data (`identity`, server paths) is declared options with types and
  descriptions, not a hand-built attrset.
- `hyprland` and `headscale` are ported and evaluated, not parked.
- No behaviour change. All six configurations build the same closures at the
  end as at the start.

## Non-goals

- Changing what any machine actually runs. This is a restructure; feature work
  and version bumps stay out of the branch.
- Touching `templates/`, `pkgs/` derivation contents, or the QML sources.
- Converting every leaf of `cfg.path.*` into an individually declared option
  (see "Server paths" below).
- Any transitional scaffolding. The branch lands at once; the old wiring is
  not kept working in between.

## Anti-goals

Things that would make this a failure even if it evaluated:

- Hosts still needing an `imports` list to get a working desktop.
- An `enable` flag that has to be set in two places (NixOS *and* Home Manager)
  for one feature to come on.
- A module that silently does nothing because its gate defaults to `false` and
  nobody noticed.
- `import-tree` picking up something that isn't a module and failing in a way
  that only shows up on one profile.

## Constraints

These are properties of this repo, not preferences:

- **No test suite.** Verification is evaluation plus a real switch on each
  machine. `tests/laserbar/` is render fixtures driven by
  `scripts/laserbar-preview.sh`, not a framework.
- **`nix flake check` is shallow on `homeConfigurations`.** It never forces the
  generated `xdg.configFile` *text*, which is exactly where the `@token@` QML
  substitution happens. The real gate is forcing
  `activationPackage.drvPath` per profile.
- **Flakes only see tracked files.** An un-`git add`ed `.nix` file is absent
  from evaluation and the check goes green against a tree without it. During a
  migration that moves ~84 files this is the single most likely way to get a
  false pass. Add files by name; never `git add -A` — this tree habitually
  holds unrelated in-progress work.
- **Things `darkman` rewrites at runtime must not be managed by
  `xdg.configFile`**, or they become read-only store symlinks. Gating must not
  accidentally move a file into `xdg.configFile`.
- **The greeter user cannot read `/home`**, which is why `modules/qml/` is
  rendered by a NixOS module. That stays true.
- **`modules/lib/` is not modules.** It is plain functions and data
  (`palette.nix`, `qml-theme.nix`, the `swayfx` store path) `import`ed
  directly. `import-tree` must not try to import it.
- The working tree currently has uncommitted changes in `Makefile`,
  `host/profiles.nix` and `modules/home-manager/helix.nix`. Those are resolved
  (committed or stashed) before the branch starts, so the baseline is a clean
  tree.

## Target layout

```
flake.nix                     inputs + mkFlake, ~40 lines
lib/                          moved from modules/lib/ — plain functions/data
qml/                          moved from modules/qml/ — greeter QML sources
scripts/                      unchanged, not in the build graph
tests/                        unchanged, render fixtures
pkgs/                         unchanged
templates/                    unchanged
modules/
  _flake/                     flake-level plumbing (underscore: not a feature)
    options.nix               declares flake.featureModules / flake.hostModules
    packages.nix              packages.${system} from pkgs/
    pkg-sets.nix              upkgs / lpkgs via _module.args
    aggregate.nix             featuresNixos / featuresHome
    templates.nix             flake.templates
  features/
    core/                     identity, locale, xdg, ssh, sh, nix-gc, nh
    system/                   docker, tailscale, avahi, printer, nvidia, vm, …
    desktop/
      sway/                   sway, laserbar, swaync, darkman, greetd, …
      hyprland/               ported, gated off
      apps/                   firefox, zen, kitty, alacritty, thunderbird, …
    dev/                      helix, vim, zed, git, wakatime, zellij
    server/                   caddy, jellyfin, immich, rustical, calino, …
  hosts/
    personal/
      _toggles.nix            flag values, shared by both sides
      default.nix             nixosSystem + homeManagerConfiguration
      configuration.nix       NixOS entry module
      home.nix                Home Manager entry module
      hardware-configuration.nix
    oserv/   epita/   epita-light/
```

`import-tree` ignores any path whose basename starts with `_`. That is what
keeps `_toggles.nix` and the `_flake/` naming honest, and it is the escape
hatch for any future non-module file that has to live under `modules/`.

## Mechanism

### 1. flake-parts + import-tree

`flake.nix` becomes inputs plus:

```nix
outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
  systems = [ "x86_64-linux" ];
  imports = [ (inputs.import-tree ./modules) ];
};
```

Two new inputs: `flake-parts` and `import-tree`.

### 2. Every file registers a named module

A feature file does not *become* a module, it *declares* one — and one file can
declare both sides of a concern:

```nix
{ ... }: {
  flake.featureModules.nixos.sway = { pkgs, ... }: { /* programs.sway, portals */ };
  flake.featureModules.home.sway  = { pkgs, ... }: { /* keybinds, swayidle */ };
}
```

`flake.featureModules.{nixos,home}` and `flake.hostModules.{nixos,home}` are
declared in `modules/_flake/options.nix` as `lazyAttrsOf raw`, because
flake-parts does not know about Home Manager and because features and host
entry modules must be mechanically distinguishable — the aggregator imports
every feature and no host.

### 3. Everything imported, gated by options

`modules/_flake/aggregate.nix` builds the two lists:

```nix
flake.nixosModules.featuresNixos = { imports = lib.attrValues config.flake.featureModules.nixos; };
flake.homeModules.featuresHome   = { imports = lib.attrValues config.flake.featureModules.home;  };
```

Every host imports the aggregate plus its own entry module. Selection stops
being an `imports` concern and becomes a `config` concern. Each feature wraps
its body in `mkIf`:

```nix
config = lib.mkIf config.ogama.server.jellyfin.enable { ... };
```

## Option namespace

All options live under `ogama.*`. This is forced, not stylistic: a bare
`services.jellyfin.enable` or `programs.helix.enable` collides with the
nixpkgs and Home Manager options of the same name.

```
ogama.identity.{realName,user,mail,homePath,sshPubkey,sshKeyPath,isEpita,login}
ogama.server.{domain,ipv6Host}
ogama.server.paths.{ssd,hdd,backup}      the three roots
ogama.server.path                        read-only derived tree (see below)
ogama.<domain>.<feature>.enable          one per feature
```

Shared option declarations are written once as a `sharedOptions` function and
registered into both `featureModules.nixos` and `featureModules.home`, so
`ogama.identity.user` means the same thing on both sides and modules read it
from `config` instead of from a `specialArgs` attrset. `cfg` disappears;
`host/profiles.nix` disappears.

### Server paths — a deliberate compromise

`cfg.path` is a deeply nested `rec` attrset
(`cfg.path.backup.hdd.share.public_HDD_path` and so on). Declaring ~30 typed
leaf options for it would be churn with no payoff, and every call site would
change shape anyway.

Instead: three real options for the roots (`ogama.server.paths.{ssd,hdd,backup}`,
type `path`, defaults `/mnt/ssd`, `/mnt/hdd-tmp`, `/mnt/backup`) and one
read-only option `ogama.server.path` whose default *derives* the whole existing
tree from those roots and from `ogama.identity.homePath`. Call sites go from
`cfg.path.hdd.app.immich` to `config.ogama.server.path.hdd.app.immich` —
mechanical, and the shape is preserved.

This also solves `cfg-perso.server`. Today the personal profile embeds the
entire server record so backups and shares can reference server paths. Because
the derived tree is declared in a module registered on *both* sides with
defaults that do not depend on which host is evaluating, personal reads
`ogama.server.path.*` directly. One host no longer reaches into another host's
record. The `oserv` user name differs from `personal`'s, so the one path that
interpolates `homePath` (`path.ssd.share.swapsev_path`) takes the server user
explicitly rather than the evaluating host's.

### One flag, set once

`personal` and `oserv` each have a NixOS configuration *and* a Home Manager
configuration, evaluated separately. A naive port makes
`ogama.desktop.laserbar.enable` exist in both and need setting twice.

Each host therefore gets `modules/hosts/<host>/_toggles.nix` — a plain attrset
of that host's flag values, `import`ed by both its `configuration.nix` and its
`home.nix`. Underscore-prefixed, so `import-tree` leaves it alone. One place
per host to flip a feature, regardless of which side implements it.

## Desktop toggle semantics

- `ogama.desktop.sway.enable` and `ogama.desktop.hyprland.enable` select a
  compositor. An assertion rejects both at once — this is exactly the clash
  that keeps the hyprland tree parked today.
- `ogama.desktop.enable` is the internal "some compositor is on" predicate,
  defined as the `or` of the two and not meant to be set by hand.
- Every desktop piece — `laserbar`, `swaync`, `darkman`, `messages`,
  `calendar`, `greeter`, `wallpaper`, `rofi`, `gtk`, `qt` — gets its own
  `enable` defaulting to `ogama.desktop.enable`. Turning on sway gives the
  whole rig; dropping one piece is one `false`.
- Sway-bound pieces (the laser bar talks sway IPC; `greetd` launches the
  `swayfx` store path from `lib/`) default to `ogama.desktop.sway.enable`
  rather than `ogama.desktop.enable`, so they come on for sway and stay off
  for hyprland until ported.

`epita-light` stops being a near-duplicate of `epita`. Both hosts share
`epita`'s toggles; `epita-light` sets `vim`, `gtk`, `alacritty`, `zellij` and
`tools` to `false` and `kitty` to `true`. The difference becomes readable.

## Parked trees

Both are ported in this branch, behind `ogama.desktop.hyprland.enable` and
`ogama.server.headscale.enable`, both defaulting `false`. They are expected
to need real fixing — they have not been evaluated in a long time and the
hyprland tree was written against an older Home Manager. Getting them to
*evaluate* while disabled is the bar for this branch; getting them to *work*
is not.

### Where enable options are declared

`_toggles.nix` only works if every flag it sets exists on both sides. The
NixOS and Home Manager evaluations are separate module systems: setting
`ogama.desktop.laserbar.enable` in a file the NixOS side imports is an error
if only the Home Manager side declared it.

So a feature file declares its options **once** and registers that declaration
to **both** sides, while registering its implementation only to the side that
implements it:

```nix
{ ... }:
let
  options = { lib, config, ... }: {
    options.ogama.server.miniflux.enable = lib.mkEnableOption "Miniflux";
  };
in
{
  flake.featureModules.nixos.miniflux = {
    imports = [ options ];
    config = /* the implementation */;
  };
  # declaration only — nothing to do in the user environment
  flake.featureModules.home.miniflux = options;
}
```

Plain Nix, no helper, still one file per concern. The rule that follows:
`_toggles.nix` contains **only** `enable` flags, because those are the options
guaranteed to exist on both sides. Anything side-specific — a port, a
subdomain, a quota — is set in that side's entry module, where it is declared.

The alternative considered and rejected: declare every `enable` centrally in
one `features/core/toggles.nix` registered to both sides, leaving feature
files to declare only their extra options. Fewer moving parts per feature, but
adding a service then touches two files, which is the coupling this migration
exists to remove.

### Constants that exist before the module system

`packages.${system}.calino` bakes `siteUrl = "http://calino.tail.${cfg-server.domain}"`
into the build. That happens where packages are defined — outside any module
evaluation — so it cannot read `config.ogama.server.domain`.

`lib/constants.nix` holds the handful of values needed in both worlds
(`domain = "ogama.me"` and the three storage roots). `modules/_flake/packages.nix`
imports it directly; `ogama.server.domain` and `ogama.server.paths.*` take
their **defaults** from it. One source, two consumers, no circularity.

`quickshell-multimedia` keeps being built with unstable's `callPackage` — its
`quickshell` and `qt6` must come from the same nixpkgs that `upkgs.quickshell`
resolves to. That constraint is unchanged and the comment explaining it moves
with the code.

### Third-party flake modules and per-host plumbing

Modules from inputs attach in the host's own `default.nix`, next to the
`nixosSystem` / `homeManagerConfiguration` call that needs them — not in a
shared aggregate, because they differ per host:

- `oserv` NixOS: `nixos-hardware.nixosModules.dell-optiplex-3050`,
  `sops-nix.nixosModules.sops`
- `personal` / `oserv` / `epita` / `epita-light` Home Manager:
  `sops-nix.homeManagerModules.sops`

`wakatime-ls`, today an `extraSpecialArgs` entry on all four Home Manager
configurations, stops being passed around: the module that wants it reads
`inputs.wakatime-ls.packages.${pkgs.system}.default` through the `inputs`
argument flake-parts already gives it. `pkgs` instantiation, including
`allowUnfreePredicate`, moves into `modules/_flake/pkg-sets.nix`, which also
sets `upkgs` and `lpkgs` via `_module.args` instead of per-configuration
`specialArgs`.

## Order of work

One branch, no intermediate working state. Within it:

1. Capture the baseline: the six drvPaths and their output closures, on a
   clean tree, recorded in the branch.
2. Add `flake-parts` + `import-tree`; stand up `modules/_flake/` and the
   aggregators; move `modules/lib/` → `lib/` and `modules/qml/` → `qml/` and
   fix the `import` sites.
3. Port `core` and the shared options; delete `host/profiles.nix` and the
   `specialArgs` plumbing from `flake.nix`.
4. Port `system`, then `dev`, then `server`, then `desktop` (largest and most
   interdependent, so last, when the pattern is settled).
5. Convert the hosts: `_toggles.nix` per host, entry modules, `default.nix`.
6. Port the two parked trees.
7. Housekeeping that is part of the branch, not a follow-up: rename
   `host/serveur/` to `modules/hosts/oserv/` so the directory matches the
   configuration name; update the `Makefile` targets if any path moved; and
   rewrite the parts of `CLAUDE.md` and the three `docs/` runbooks that
   describe imports lists, since they are the entry point for the next
   service and the next widget.
8. Verify, then switch each machine.

## Verification gate

Nothing is switched until all of this passes:

```
nix flake check
nix eval --raw .#nixosConfigurations.personal.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.oserv.config.system.build.toplevel.drvPath
nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath
nix eval --raw .#homeConfigurations.oserv.activationPackage.drvPath
nix eval --raw .#homeConfigurations.epita.activationPackage.drvPath
nix eval --raw .#homeConfigurations.epita-light.activationPackage.drvPath
```

All six must evaluate — they all do today, including `oserv`, which runs
immich 3.3.5 from `upkgs` and needs no `permittedInsecurePackages`.

Evaluation is necessary but not sufficient: a feature whose gate defaults
`false` by mistake evaluates fine and silently vanishes. So the real gate is
closure comparison against the recorded baseline:

```
nix store diff-closures /nix/store/<baseline> /nix/store/<new>
```

For each of the six, the diff must be empty of package additions and
removals. A moved file can change an embedded store path and so a drvPath
without changing behaviour, which is why the gate is the closure diff rather
than drvPath equality. Anything the diff shows must be explained before the
branch lands, not after.

Then, and only then: `make personal`, `make oserv`, `make epita` on the real
machines, with the laser bar render harness
(`scripts/laserbar-preview.sh`, `scripts/laserbar-probe.sh`) run on the
desktop before trusting it.

The three runbooks in `docs/` (`adding-a-server-service.md`,
`adding-a-bar-widget.md`, `theming.md`) describe the old imports-list world
and are updated in this branch, since they are the entry points for the next
service and the next widget.

## Calls I made

Flagged so they can be overridden on reading:

- `ogama.*` as the namespace prefix. Forced by collisions; the name is mine.
- `ogama.server.path` as one derived read-only option rather than ~30 typed
  leaves. Keeps call sites mechanical.
- `_toggles.nix` per host as the single place a flag is set, rather than
  setting flags twice or coupling the two configurations together.
- `featureModules` / `hostModules` as separate option trees, rather than
  filtering host entry modules out of `flake.nixosModules` by name.
- `sway`/`hyprland` as mutually exclusive via an assertion, rather than an
  enum option. An enum reads better but makes "no compositor" (oserv, epita)
  a third value to handle everywhere.
- Desktop pieces default *on* with the compositor. The alternative — default
  off, opt in — is safer against silent loss but reintroduces a list per host.
  The closure diff is what catches silent loss instead.
- `lib/` and `qml/` move to the repo root rather than becoming
  `modules/_lib/`. They are not modules and do not belong under `modules/`.
- Options declared once per feature and registered to both sides, rather than
  a central toggle registry. Keeps "one concern, one file" true.
- `lib/constants.nix` as the pre-module source for `domain` and the storage
  roots, because `packages.calino` needs the domain before any module exists.
- `host/serveur/` renamed to `hosts/oserv/`. The mismatch between the
  directory name and the configuration name is a long-standing papercut and
  this is the branch that is already moving the file.

## Left to the builder

- Exact file-to-file mapping of the 84 current module files into
  `features/{core,system,desktop,dev,server}/`. The domains are fixed; which
  bucket each file lands in is a judgement call.
- Whether a given concern's NixOS and Home Manager halves genuinely belong in
  one file or read better as two in the same directory.
- Option naming below the `ogama.<domain>.<feature>` level.
- How far to go in fixing the hyprland tree once it starts evaluating.
