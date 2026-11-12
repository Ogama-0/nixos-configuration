# flake-parts + import-tree Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure this flake so every module is always imported and always evaluated, and what a machine runs is a set of `ogama.*.enable` flags — with all six configurations producing byte-identical closures at the end.

**Architecture:** `flake.nix` becomes inputs plus `flake-parts.lib.mkFlake` with `imports = [ (import-tree ./modules) ]`. Each file under `modules/` registers a named module into `flake.featureModules.{nixos,home}`; an aggregator imports every one of them into every host unconditionally; each module gates its body on `lib.mkIf config.ogama.<domain>.<feature>.enable`. Per-host data becomes declared options read off `config`, replacing the `cfg` attrset threaded through `specialArgs`.

**Tech Stack:** Nix flakes, flake-parts, vic/import-tree, NixOS + Home Manager module systems, sops-nix.

**Spec:** `docs/superpowers/specs/2026-11-13-flake-parts-options-migration-design.md`
**Example module:** `docs/superpowers/specs/2026-11-13-example-service-module.nix`

## Global Constraints

- **No behaviour change.** Every task ends with `nix store diff-closures` empty for all six configurations. A non-empty diff is a failed task, not a surprise to explain later.
- **The six configurations:** `nixosConfigurations.{personal,oserv}`, `homeConfigurations.{personal,oserv,epita,epita-light}`. All six evaluate today.
- **Option namespace is `ogama.*`.** Never a bare `services.*` / `programs.*` / `desktop.*` name.
- **`git add` new and moved files BY NAME. Never `git add -A`** — this tree habitually holds unrelated in-progress work, and an unadded `.nix` file is invisible to the flake, so the check passes against a tree without it.
- **`import-tree` ignores paths whose basename starts with `_`.** That is the only mechanism keeping non-modules out of the import root.
- **`nix flake check` is not a gate.** It shallow-checks `homeConfigurations` and never forces the generated `xdg.configFile` text where the `@token@` QML substitution happens. The gate is forcing `activationPackage.drvPath` per profile.
- **Anything `darkman` rewrites at runtime must not be managed by `xdg.configFile`** or it becomes a read-only store symlink darkman cannot replace. See `docs/theming.md`.
- **The greeter user cannot read `/home`**, which is why the greeter QML is rendered by a NixOS module. That stays true after the `qml/` move.
- Storage roots are `/mnt/ssd`, `/mnt/hdd-tmp`, `/mnt/backup`. Domain is `ogama.me`.

## Review Focus

Failure modes the spec implies that no task's primary check would catch. Each has a test pinned to the task that owns the code.

1. **A new or moved file left untracked** makes every check pass against a tree that does not contain it. Owned by Task 2; every task's commit step verifies `git status --porcelain` lists no untracked `.nix` under `modules/`, `lib/` or `qml/`.
2. **An option declared on only one side** makes `_toggles.nix` a hard error on the other side, and only for the host that sets that flag — so it can pass on `oserv` and fail on `personal`. Owned by Task 4: a check that sets every declared flag in one host's toggles and evaluates both that host's NixOS and Home Manager configuration.
3. **A gate that defaults `false` by mistake** drops a feature silently and still evaluates. Owned by every porting task via the closure diff — plus Task 5's explicit assertion step, because `epita` has no NixOS configuration and so a NixOS-only regression cannot show up there at all.
4. **A darkman target accidentally promoted to `xdg.configFile`** during gating produces a working build and a desktop whose light mode no longer switches. Owned by Task 9: an explicit check that darkman's rewritten paths appear in no `xdg.configFile` attribute.
5. **A non-module file under `modules/` without the `_` prefix** gets imported by `import-tree` and fails in whichever evaluation reaches it first. Owned by Task 4: a check that every path under `modules/` either ends in `.nix` and registers a module, or starts with `_`.

---

## File Structure

**New:**
- `lib/constants.nix` — `domain` and the three storage roots; the pre-module source of truth.
- `modules/_flake/options.nix` — declares `flake.featureModules.{nixos,home}`, `flake.hostModules.{nixos,home}`, `flake.homeConfigurations`, `flake.homeModules`.
- `modules/_flake/pkg-sets.nix` — `pkgs` instantiation with `allowUnfreePredicate`, plus `upkgs` / `lpkgs` via `_module.args`.
- `modules/_flake/packages.nix` — `packages.${system}` from `pkgs/`.
- `modules/_flake/aggregate.nix` — `flake.nixosModules.featuresNixos` / `flake.homeModules.featuresHome`.
- `modules/_flake/templates.nix` — `flake.templates`.
- `modules/hosts/<host>/{default.nix,_toggles.nix}` for `personal`, `oserv`, `epita`, `epita-light`.
- `modules/features/core/shared-options.nix` — `ogama.identity.*`, `ogama.server.*`, registered to both sides.

**Moved:** `modules/lib/` → `lib/`; `modules/qml/` → `qml/`; `host/personal/` → `modules/hosts/personal/`; `host/serveur/` → `modules/hosts/oserv/`; `host/epita/` → `modules/hosts/epita/`; the 84 files under `modules/{nixosconf,home-manager}/` → `modules/features/{core,system,desktop,dev,server}/`.

**Deleted:** `host/profiles.nix`, `modules/nixosconf/`, `modules/home-manager/`, `host/`.

---

### Task 1: Clean baseline

**Files:**
- Create: `docs/superpowers/plans/_baseline-2026-11-13.md` (underscore: never imported)

- [ ] **Step 1: Resolve the dirty tree**

`Makefile`, `host/profiles.nix` and `modules/home-manager/helix.nix` have uncommitted changes. Commit them on `main` if they are finished work, otherwise `git stash push` them by name. Ask the user which — do not guess, and do not discard.

- [ ] **Step 2: Verify the tree is clean and pull**

Run: `git status --porcelain && git pull --ff-only`
Expected: no output from the first command, then a successful pull.

- [ ] **Step 3: Branch**

Run: `git switch -c flake-parts-migration`

- [ ] **Step 4: Record the baseline drvPaths**

Run, for each of the six:

```bash
nix eval --raw .#nixosConfigurations.personal.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.oserv.config.system.build.toplevel.drvPath
nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath
nix eval --raw .#homeConfigurations.oserv.activationPackage.drvPath
nix eval --raw .#homeConfigurations.epita.activationPackage.drvPath
nix eval --raw .#homeConfigurations.epita-light.activationPackage.drvPath
```

Expected: six store paths, no errors.

- [ ] **Step 5: Build and record the baseline closures**

Build all six (`nix build --no-link --print-out-paths` on the same attributes without `.drvPath`). This is the slow step — `personal` pulls the nvidia module, which must build against the LTS kernel, not `linuxPackages_latest`. Record the six output paths in `_baseline-2026-11-13.md` alongside the drvPaths.

- [ ] **Step 6: Write the verification script**

Create `scripts/migration-check.sh`: evaluates all six drvPaths, builds all six, and runs `nix store diff-closures <baseline> <new>` for each against the paths recorded in `_baseline-2026-11-13.md`. Exits non-zero if any evaluation fails or any diff is non-empty. Every later task's verification step is one run of this script.

- [ ] **Step 7: Verify the script passes against the unmodified tree**

Run: `./scripts/migration-check.sh`
Expected: exit 0, six empty diffs. If it does not pass here it is the script that is wrong, not the tree.

- [ ] **Step 8: Commit**

```bash
git add docs/superpowers/plans/_baseline-2026-11-13.md scripts/migration-check.sh
git commit -m "chore(migration): record baseline closures and check script"
```

---

### Task 2: flake-parts skeleton, with hosts still pointing at the old entry modules

Behaviour-preserving by construction: the new `flake.nix` builds the same six configurations from the same existing entry modules. Only the plumbing changes.

**Files:**
- Modify: `flake.nix` (replace the whole `outputs` body)
- Create: `modules/_flake/{options,pkg-sets,packages,templates}.nix`, `lib/constants.nix`
- Create: `modules/hosts/{personal,oserv,epita,epita-light}/default.nix`
- Move: `modules/lib/` → `lib/`, `modules/qml/` → `qml/`
- Move: `host/personal/` → `modules/hosts/personal/`, `host/serveur/` → `modules/hosts/oserv/`, `host/epita/` → `modules/hosts/epita/`
- Modify: the 9 files that `import ../lib/*` or reference `../qml/*` (see Step 5)

**Interfaces:**
- Produces: `_module.args.upkgs`, `_module.args.lpkgs`, `_module.args.cfg` (the latter is temporary scaffolding, removed in Task 3). `flake.featureModules.{nixos,home}` and `flake.hostModules.{nixos,home}` as `lazyAttrsOf raw`. `lib/constants.nix` → `{ domain, paths = { ssd, hdd, backup }; }`.

- [ ] **Step 1: Add the inputs**

Add to `flake.nix` inputs: `flake-parts.url = "github:hercules-ci/flake-parts"` and `import-tree.url = "github:vic/import-tree"`.

- [ ] **Step 2: Run the check to see it fail**

Run: `./scripts/migration-check.sh`
Expected: FAIL — `flake.lock` is stale. Run `nix flake lock` and re-run; it should pass again, with the two new inputs locked.

- [ ] **Step 3: Move `modules/lib/` to `lib/` and `modules/qml/` to `qml/`**

Use `git mv` so the moves are tracked.

- [ ] **Step 4: Rename the host directories**

`git mv host/personal modules/hosts/personal`, `git mv host/serveur modules/hosts/oserv`, `git mv host/epita modules/hosts/epita`. Leave `host/profiles.nix` where it is for now — Task 3 deletes it.

- [ ] **Step 5: Fix every reference to the moved trees**

The relative-path importers, all of which change depth:

```
modules/features/.../darkman.nix          ../lib/{alacritty-colors,quickshell-tree-link,helix-auto-theme,zellij-theme,timezone-coords}.nix
modules/features/.../alacritty.nix        ../lib/alacritty-colors.nix
modules/features/.../helix.nix            ../lib/helix-auto-theme.nix
modules/features/.../zellij/default.nix   ../../lib/zellij-theme.nix
modules/features/.../vicinae.nix          ../../lib/theme-colors.nix
modules/features/.../hyprland/swaync.nix  ../../../lib/theme-colors.nix
modules/features/.../hyprland/waybar.nix  ../../../lib/theme-colors.nix
modules/features/.../sway/default.nix     ../../../lib/swayfx.nix
modules/features/.../sway/quickshell/default.nix  ../../../../lib/{theme-colors,palette,qml-theme,quickshell-tree-link,swayfx}.nix
modules/nixosconf/greetd.nix              ../lib/{qml-theme,theme-colors,swayfx}.nix and ../qml/{GreeterDark,GreeterLight}.qml, ../qml/components/GreetdSession.qml
```

Modules have not moved into `features/` yet at this point, so the depth change here is only the one caused by `lib/` and `qml/` leaving `modules/`.

- [ ] **Step 6: Write `lib/constants.nix`**

`{ domain = "ogama.me"; paths = { ssd = "/mnt/ssd"; hdd = "/mnt/hdd-tmp"; backup = "/mnt/backup"; }; }`. Nothing imports it yet except Step 8.

- [ ] **Step 7: Write `modules/_flake/options.nix`**

Declare `flake.featureModules.nixos`, `flake.featureModules.home`, `flake.hostModules.nixos`, `flake.hostModules.home`, `flake.homeConfigurations`, `flake.homeModules` — each `lib.types.lazyAttrsOf lib.types.raw`, default `{ }`, with a description. flake-parts knows `nixosModules` and `nixosConfigurations`; it does not know the Home Manager ones or ours.

- [ ] **Step 8: Write `modules/_flake/pkg-sets.nix` and `packages.nix`**

`pkg-sets.nix` instantiates `pkgs` from `nixpkgs` with `config.allowUnfreePredicate = _: true`, builds `upkgs` (unstable, plus `zen-browser` and `quickshell` from their flakes) and `lpkgs` (this flake's own packages), and exposes all three plus the temporary `cfg` through `_module.args`.

`packages.nix` moves `packages.${system}` across verbatim, with two comments preserved because they are load-bearing: `calino` takes `siteUrl` from `lib/constants.nix` (`"http://calino.tail.${constants.domain}"`) because the URL is baked at build time and cannot read an option; `quickshell-multimedia` keeps unstable's `callPackage` so its `quickshell` and `qt6` match `upkgs.quickshell`.

- [ ] **Step 9: Write the four `modules/hosts/<host>/default.nix`**

Each registers its configuration and nothing else — `nixosSystem` / `homeManagerConfiguration` with `modules` pointing at the *existing* entry module (`./configuration.nix`, `./home.nix`, `./epita.nix`, `./epita_light.nix`) plus the third-party flake modules that host needs: `nixos-hardware.nixosModules.dell-optiplex-3050` and `sops-nix.nixosModules.sops` for `oserv` NixOS; `sops-nix.homeManagerModules.sops` for all four Home Manager configurations. `wakatime-ls` stays an `extraSpecialArgs` entry at this point.

- [ ] **Step 10: Replace the `outputs` body of `flake.nix`**

Inputs plus `mkFlake { systems = [ "x86_64-linux" ]; imports = [ (inputs.import-tree ./modules/_flake) ]; }`. Note the root is `./modules/_flake`, not `./modules` — `import-tree` would otherwise try to import the 84 unported module files as flake-parts modules. Widening the root to `./modules` is Task 4.

- [ ] **Step 11: Stage every new and moved file by name, then verify**

Run: `git status --porcelain` and confirm nothing under `modules/`, `lib/` or `qml/` is listed as untracked. Then run `./scripts/migration-check.sh`.
Expected: exit 0, six empty closure diffs. A non-empty diff here means a moved `lib/` file changed a store path that gets embedded in generated config — investigate before continuing; do not accept it.

- [ ] **Step 12: Commit**

```bash
git add flake.nix flake.lock lib qml modules/_flake modules/hosts modules/nixosconf modules/home-manager
git commit -m "refactor(flake): adopt flake-parts, move lib/ and qml/ out of modules/"
```

---

### Task 3: Shared options replace `cfg`

The largest single task and not divisible: `cfg` is passed as one value, so the 35 files that read it convert together.

**Files:**
- Create: `modules/features/core/shared-options.nix`
- Delete: `host/profiles.nix`
- Modify: the 35 files matching `grep -rl '\bcfg\.' --include=*.nix modules`
- Modify: `modules/_flake/pkg-sets.nix` (drop the temporary `_module.args.cfg`)

**Interfaces:**
- Consumes: `lib/constants.nix` from Task 2.
- Produces: `config.ogama.identity.{realName,user,mail,homePath,sshPubkey,sshKeyPath,isEpita,login}`, `config.ogama.server.{domain,ipv6Host}`, `config.ogama.server.paths.{ssd,hdd,backup}`, `config.ogama.server.path` (read-only derived tree). Every later task reads these.

- [ ] **Step 1: Write the option declarations**

`shared-options.nix` defines a single `sharedOptions` function and registers it to both `flake.featureModules.nixos.sharedOptions` and `flake.featureModules.home.sharedOptions`, so the names mean the same thing on both sides.

Types: `str` for identity fields, `path` for `homePath`/`sshKeyPath`/the three roots, `bool` for `isEpita`. Defaults: `realName = "Oscar Cornut"`, `mail = "oscar.cornut@gmail.com"`, `homePath = "/home/${config.ogama.identity.user}"`, `sshKeyPath` derived from `homePath`, `domain` and `paths.*` from `lib/constants.nix`, `ipv6Host = "ipv6.${config.ogama.server.domain}"`. `user` and `sshPubkey` have no default — each host sets them.

`ogama.server.path` is `lib.mkOption { type = lib.types.raw; readOnly = true; default = <the derived tree>; }`, reproducing the current shape of `cfg.path` exactly — `ssd`, `hdd`, `backup` with the same leaf names, derived from `paths.*`. The one leaf that interpolates a home directory (`path.ssd.share.swapsev_path`, today `${base.home_path}/swapsev`) takes the *server* user explicitly, `"/home/ogama_serv/swapsev"`, because `personal` reads this tree too and must not get its own home path substituted.

- [ ] **Step 2: Add the aggregate import so the options exist**

Nothing imports `featureModules` yet. Temporarily add `self.featureModules.nixos.sharedOptions` / `.home.sharedOptions` to each host's `default.nix` module list. Task 4 replaces this with the real aggregator.

- [ ] **Step 3: Run the check to see the options land without being used**

Run: `./scripts/migration-check.sh`
Expected: exit 0 — declaring unused options changes nothing. If it fails, the derived tree is forcing something it should not.

- [ ] **Step 4: Set the identity in each host**

In each host's entry module (both sides for `personal` and `oserv`): `ogama.identity.user` = `ogama` / `ogama_serv` / `oscar.cornut`, the matching `sshPubkey` from the deleted `profiles.nix`, `isEpita = true` and `login = "oscar.cornut"` for the epita hosts.

- [ ] **Step 5: Convert the call sites**

Mechanical, by frequency: `cfg.user` (46) → `config.ogama.identity.user`, `cfg.domain` (33) → `config.ogama.server.domain`, `cfg.home_path` (16) → `config.ogama.identity.homePath`, `cfg.server.domain` (10) → `config.ogama.server.domain`, `cfg.path.*` → `config.ogama.server.path.*`, `cfg.ssh.pubkey` → `config.ogama.identity.sshPubkey`, `cfg.ssh.path.{priv,pub}` → derived from `sshKeyPath`, `cfg.login` → `config.ogama.identity.login`, `cfg.mail` → `config.ogama.identity.mail`, `cfg.host.ipv6` → `config.ogama.server.ipv6Host`, `cfg.share.*` → `config.ogama.server.path.*`.

Two call sites need judgement rather than substitution: `cfg.settings` (1 occurrence) and `cfg.server.path.backup.laptop.document` (1) — read those in context and keep the meaning.

Remove `cfg` from every module's argument list as you go.

- [ ] **Step 6: Delete the scaffolding**

Delete `host/profiles.nix`, remove `_module.args.cfg` from `pkg-sets.nix`, and remove the `host/` directory if now empty.

- [ ] **Step 7: Verify**

Run: `./scripts/migration-check.sh`
Expected: exit 0, six empty diffs. A diff showing a changed path is a mistranslated `cfg.path.*` leaf — the derived tree must reproduce the old strings character for character.

- [ ] **Step 8: Commit**

```bash
git add modules lib flake.nix
git rm host/profiles.nix
git commit -m "refactor(options): replace the cfg attrset with declared ogama.* options"
```

---

### Task 4: The aggregator, `_toggles.nix`, and the widened import root

After this task selection is possible but nothing is selected yet.

**Files:**
- Create: `modules/_flake/aggregate.nix`
- Create: `modules/hosts/<host>/_toggles.nix` × 4
- Modify: `flake.nix` (import root), the four `default.nix`, the host entry modules

- [ ] **Step 1: Write the aggregator**

`flake.nixosModules.featuresNixos = { imports = lib.attrValues config.flake.featureModules.nixos; }` and the same for `home`. Unconditional: every registered feature is imported into every host of that kind.

- [ ] **Step 2: Wire the aggregator and the toggles**

Each host's NixOS module list gets `self.nixosModules.featuresNixos`; each Home Manager list gets `self.homeModules.featuresHome`. Both of a host's entry modules get `imports = [ ./_toggles.nix ]`. Create the four `_toggles.nix` as empty attrsets `{ }` for now.

- [ ] **Step 3: Widen the import root**

Change `flake.nix` to `imports = [ (inputs.import-tree ./modules) ]`. The 84 unported files under `modules/nixosconf/` and `modules/home-manager/` are *not* flake-parts modules and will break this — which is why they move in Tasks 5–9. To keep this task green, pass `import-tree`'s filter so it only descends `_flake`, `features` and `hosts`, and remove the filter in Task 9 once `nixosconf/` and `home-manager/` are empty.

- [ ] **Step 4: Prove the both-sides rule holds**

Write `scripts/migration-toggles-check.sh`: for `personal`, generate a `_toggles.nix` that sets every `ogama.*.enable` option declared on *either* side to its current value, then evaluate both `nixosConfigurations.personal` and `homeConfigurations.personal`. An option declared on only one side fails here, loudly, instead of failing later on one host only.

- [ ] **Step 5: Prove the `_` rule holds**

Add to `scripts/migration-check.sh`: every path under `modules/` must either end in `.nix` and sit under `features/`, `hosts/` or `_flake/`, or have a basename starting with `_`. Fail otherwise.

- [ ] **Step 6: Verify**

Run: `./scripts/migration-check.sh && ./scripts/migration-toggles-check.sh`
Expected: both exit 0. With no features registered, both scripts pass trivially — that is the point; they must be in place *before* features start moving.

- [ ] **Step 7: Commit**

```bash
git add modules flake.nix scripts/migration-check.sh scripts/migration-toggles-check.sh
git commit -m "feat(flake): add the feature aggregator and per-host toggles"
```

---

### Tasks 5–9: Port the features, one domain per task

Five tasks with identical shape. Do them in this order — `core` is smallest and settles the pattern, `desktop` is largest and most interdependent and goes last.

| Task | Domain | Files from | Notes |
|---|---|---|---|
| 5 | `features/core/` | `home-manager/{sh,git,nh,nix-gc,keyboard}.nix`, `nixosconf/{ssh,nh,utilities}.nix`, `hosts/*/home-manager/tool*.nix`, `hosts/epita/tools.nix` | `nh` exists on both sides — merge the pair into one file. `wakapi` merges in Task 8, not here (see ledger ruling) |
| 6 | `features/system/` | `nixosconf/{docker,tailscale,avahi,mounting,nvidia,printer,geoclue,earlyoom,vm,steam,localsend,kdeconnect,postgresql-collation,samba,samba-cli,gns3-root,stream}.nix` | `postgresql-collation` must apply wherever `services.postgresql` runs: default its enable to `config.services.postgresql.enable` rather than making it a host flag |
| 7 | `features/dev/` | `home-manager/{helix,vim,zed-editor,gns3,joplin-desktop}.nix`, `zellij/` | `helix.nix` has uncommitted work resolved in Task 1; this task also drops `wakatime-ls` from `extraSpecialArgs` (Step 2c) |
| 8 | `features/server/` | `nixosconf/{caddy,jellyfin,immich,wakapi,rustical,calendar-syncer,calino,joplin-server,status-page,la-scene-interieure,qbittorrent,crafty}.nix`, `home-manager/wakapi.nix`, `hosts/oserv/nixosconf/grafana.nix` | `joplin-server` and `crafty` need docker: default their enable to `false` and assert `ogama.system.docker.enable` when on. `wakapi`'s two halves merge into one `features/server/wakapi.nix` |
| 9 | `features/desktop/` | `home-manager/{firefox,kitty,alacritty,thunderbird,gammastep,darkman,display/*}.nix`, `nixosconf/{greetd,gtklock}.nix` | Largest. `display/sway/quickshell/` carries the bar, messages panel, calendar and status widget |

For **each** of Tasks 5–9:

- [ ] **Step 1: Move the files**

`git mv` each file into its `features/<domain>/` home. Merge both-sides pairs into one file in the same move.

- [ ] **Step 2: Convert each file to a registered, gated module**

Per `docs/superpowers/specs/2026-11-13-example-service-module.nix`: a `sharedOptions` binding declaring `.enable` registered to **both** `featureModules.nixos.<name>` and `featureModules.home.<name>`; the implementation registered only to the side that implements it; the whole body under `lib.mkIf cfg.enable`. Options beyond `.enable` are declared on the side that uses them.

Default each `.enable` to `false` except where the table above says otherwise, and except desktop pieces in Task 9 (see Step 2a).

- [ ] **Step 2a (Task 9 only): The compositor options**

`ogama.desktop.sway.enable` and `ogama.desktop.hyprland.enable`, plus `ogama.desktop.enable` defined as the `or` of the two and documented as not-for-hand-setting, plus an assertion rejecting both at once. Every desktop piece defaults to `ogama.desktop.enable`; the sway-bound ones — `laserbar`, `greeter`, `effects`, `idle` — default to `ogama.desktop.sway.enable` instead, because the bar talks sway IPC and `greetd` execs the `swayfx` store path from `lib/swayfx.nix`.

- [ ] **Step 2c (Task 7 only): Stop passing `wakatime-ls` around**

`wakatime-ls` is an `extraSpecialArgs` entry on all four Home Manager configurations today, consumed by the helix and zed modules. Those modules read `inputs.wakatime-ls.packages.${pkgs.system}.default` through the `inputs` argument flake-parts already provides, and the entry is deleted from all four `modules/hosts/<host>/default.nix`.

- [ ] **Step 2b (Task 8 only): Move monitoring registration into each service**

Declare `ogama.server.statusPage.endpoints` (`listOf attrs`) and `ogama.server.processExporter.matchers` (`listOf attrs`); `status-page.nix` and `grafana.nix` consume the merged lists. Then move each service's gatus endpoint and process matcher out of those two central files into the service's own file. The `comm` values move verbatim — they are already correct for the wrapper names actually on disk, and re-deriving them is how they silently stop matching.

- [ ] **Step 3: Flip the flags on in `_toggles.nix`**

For each host, set to `true` exactly the features whose files that host's old `imports` list contained — and nothing more. The old lists are the specification for this step; read them from git history, not from memory. Delete each ported path from the host's `imports` list in the same edit.

- [ ] **Step 4 (Task 9 only): Check darkman's targets**

Run `grep -rn 'xdg.configFile' modules/features/desktop/` and confirm none of the paths darkman rewrites at runtime appear there. `docs/theming.md` lists them. A store symlink in one of those positions builds fine and breaks light mode.

- [ ] **Step 5: Verify**

Run: `./scripts/migration-check.sh && ./scripts/migration-toggles-check.sh`
Expected: both exit 0, six empty closure diffs. A removal in a diff is a flag left `false`; an addition is a flag set `true` that the host did not previously import.

- [ ] **Step 6: Commit**

```bash
git add modules
git commit -m "refactor(<domain>): port to gated feature modules"
```

(Task 9's commit also removes the `import-tree` filter from `flake.nix`, since `modules/nixosconf/` and `modules/home-manager/` are empty by then.)

---

### Task 10: Collapse `epita-light`

**Files:**
- Modify: `modules/hosts/epita/_toggles.nix`, `modules/hosts/epita-light/_toggles.nix`
- Delete: `modules/hosts/epita/epita_light.nix`

- [ ] **Step 1: Diff the two old imports lists**

From git history: `epita_light` is `epita` minus `vim`, `display/gtk`, `alacritty`, `zellij` and `tools`, plus `kitty`.

- [ ] **Step 2: Express that as flags**

`epita-light/_toggles.nix` imports `../epita/_toggles.nix` and overrides those six flags. Delete `epita_light.nix`; its host `default.nix` now points at `../epita/epita.nix`.

- [ ] **Step 3: Verify**

Run: `./scripts/migration-check.sh`
Expected: exit 0. `homeConfigurations.epita-light`'s closure is the one most likely to drift here — its diff must be empty, not merely small.

- [ ] **Step 4: Commit**

```bash
git add modules
git rm modules/hosts/epita/epita_light.nix
git commit -m "refactor(epita): express epita-light as flags instead of a second imports list"
```

---

### Task 11: Port the two parked trees

They have not been evaluated in a long time. The bar is that they **evaluate while disabled**, not that they work.

**Files:**
- Move: `modules/home-manager/display/hyprland/` → `modules/features/desktop/hyprland/` (9 files)
- Move: `modules/nixosconf/headscale.nix` → `modules/features/server/headscale.nix`

- [ ] **Step 1: Move and register them**

Gate the hyprland tree on `ogama.desktop.hyprland.enable` (declared in Task 9) and headscale on `ogama.server.headscale.enable`, both defaulting `false`. Both are set nowhere.

- [ ] **Step 2: Run the check to see them fail**

Run: `./scripts/migration-check.sh`
Expected: FAIL. These are written against an older Home Manager and have never coexisted with sway in one evaluation. Expect option renames and removed options.

- [ ] **Step 3: Fix until they evaluate**

Fix only what blocks evaluation. Resist improving them; that is a separate piece of work and this branch is already large.

- [ ] **Step 4: Verify**

Run: `./scripts/migration-check.sh`
Expected: exit 0, six empty diffs — gated off, they contribute nothing to any closure. A non-empty diff means something in them is escaping its `mkIf`.

- [ ] **Step 5: Commit**

```bash
git add modules
git commit -m "feat(desktop,server): port the parked hyprland and headscale trees behind disabled flags"
```

---

### Task 12: Documentation and Makefile

The runbooks are the entry point for the next service and the next widget, and they currently describe a world that no longer exists.

**Files:**
- Modify: `CLAUDE.md`, `Makefile`
- Modify: `docs/adding-a-server-service.md`, `docs/adding-a-bar-widget.md`, `docs/theming.md`

- [ ] **Step 1: Rewrite the `CLAUDE.md` Architecture section**

Describe the new layout. Delete the two paragraphs that no longer hold: the one about `host/profiles.nix` being the single source of per-user truth, and the one listing `modules/home-manager/display/hyprland/` and `modules/nixosconf/headscale.nix` as unreachable and unchecked — they are now imported and evaluated. Keep and update the warnings about `nix flake check` being shallow and flakes ignoring untracked files; both still apply.

- [ ] **Step 2: Update the runbooks**

`adding-a-server-service.md` points at the example module and the one-line toggle, and records that gatus and process-exporter registration now lives in the service's own file. `adding-a-bar-widget.md` gains the enable-option step. `theming.md`'s one-palette rule is unchanged, but the paths move from `modules/lib/` to `lib/`.

- [ ] **Step 3: Check the Makefile**

The five targets call `nh` with flake references, which have not changed. Confirm no target references a moved path.

- [ ] **Step 4: Verify the docs' commands actually run**

Run every command quoted in the three runbooks and in `CLAUDE.md`. A runbook with a stale path is the failure mode this task exists to prevent.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md Makefile docs
git commit -m "docs: describe the flake-parts + options layout"
```

---

### Task 13: Final verification and switch

- [ ] **Step 1: Full check from a clean tree**

Run: `git status --porcelain` (expect empty), then `./scripts/migration-check.sh && ./scripts/migration-toggles-check.sh && nix flake check`
Expected: all three exit 0, six empty closure diffs.

- [ ] **Step 2: Confirm nothing is untracked**

Run: `git ls-files --others --exclude-standard`
Expected: no `.nix` file under `modules/`, `lib/` or `qml/`. This is the one failure mode that makes every check above meaningless.

- [ ] **Step 3: Render-test the bar before trusting the desktop**

Run `scripts/laserbar-preview.sh` and `scripts/laserbar-probe.sh` against `tests/laserbar/`. The closure diff proves the generated QML text is unchanged, but these prove it still renders.

- [ ] **Step 4: Switch, one machine at a time**

`make personal` on the desktop. Confirm the bar, light/dark switching via darkman, and a reboot through the greeter — the greeter is the one surface no check above exercises, because the greeter user cannot read `/home`. Then `make oserv`, then `make epita`.

- [ ] **Step 5: Ask before each switch**

Confirm with the user before every `make` target. Do not switch unprompted.

---

## Notes for the executor

- The closure diff is the whole test suite. If a task cannot be made to produce an empty diff, stop and report rather than accepting the diff — the one thing this branch promises is that nothing changes.
- `scripts/migration-check.sh` and `scripts/migration-toggles-check.sh` are migration scaffolding. Deleting them is a follow-up commit after the switches succeed, not part of this plan.
- `_baseline-2026-11-13.md` stays in the branch so the diffs are reproducible.
