# Drop stylix / runtime darkman theming — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove stylix entirely and make darkman drive real runtime light/dark switching across GTK, alacritty, the quickshell bar/widgets/lockscreen, mako, zen and vicinae, with the system dark palette taken from the existing terminal colours and wallpapers split into dark/light/both pools.

**Architecture:** stylix is build-time and pins `polarity = "dark"`, so it structurally cannot switch at runtime; it is deleted. `modules/lib/theme-colors.nix` becomes the single palette source. Three switching mechanisms, each with an existing precedent in this repo: dconf/portal writes (GTK, zen, vicinae), content-rewrite plus live reload (alacritty, mako), and generate-both-variants plus symlink plus service restart (quickshell). `modules/lib/qml-theme.nix` already takes `colors` as a parameter, so generating two complete quickshell trees requires no QML edits.

**Tech Stack:** Nix flakes, home-manager, darkman, dconf, Quickshell/QML, alacritty 0.17, mako, sway.

**Spec:** `docs/superpowers/specs/2026-10-14-drop-stylix-runtime-theming-design.md`

## Global Constraints

- Scope is the `personal` profile. `oserv`, `epita`, `epita-light` get no intentional changes — but `epita` imports `modules/home-manager/display/i3`, which holds a Nix path literal into `assets/wallpaper/`, so Task 2 must keep `epita` evaluating.
- **Any file darkman rewrites at runtime must not be managed by home-manager.** A managed path becomes a read-only Nix store symlink. Precedent and rationale: the `settings = { }` comment in `modules/home-manager/darkman.nix`, and the `color-scheme` comment in `modules/home-manager/display/gtk.nix`. Seed such files with `home.activation` instead.
- There is no test suite in this repo (`CLAUDE.md`). The test cycle for every task is `nix eval` assertions against generated config text, plus `nix flake check`. Assertion harness verified working: `nix eval --impure --expr` can read `homeConfigurations.personal.config.xdg.configFile."<path>".text`.
- **A green `nix flake check` does not prove the generated QML is valid.** Nix never parses the substituted output. Only Task 8's live round-trip validates it.
- Light palette: Horizon light, unchanged. Dark palette: replaced by the terminal-derived palette (Task 1).
- UI accent (`base0D`) in dark mode is blue `#008DF8`, deliberately replacing Horizon's pink-red `#DF5273`.
- `theme-colors.nix` writes hex **uppercase** without a `#`; stylix emitted **lowercase**. Generated QML will change case (e.g. `#FFdf5273` to `#FF008DF8`). This is cosmetic — QML's colour parser is case-insensitive — but all assertions in this plan must match the uppercase form.
- Never run `nixos-rebuild switch` or `home-manager switch` without asking the user first.

## Review Focus

1. **A missing `assets/wallpaper/dark/` or `light/` directory** makes `find` write `No such file or directory` to stderr on every quickshell start, and can empty the pool. Git does not track empty directories. Pinned in Task 2.
2. **A darkman script writing to a home-manager-managed path** silently fails against a read-only store symlink. Applies to `alacritty/colors.toml` and the quickshell tree symlink. Pinned in Tasks 4 and 7.
3. **`home.activation.darkmanTimezoneSync`'s `entryAfter` references `quickshellLockDefault`**, which Task 7 deletes. A dangling activation dependency breaks activation. Pinned in Task 7.
4. **An empty wallpaper pool for one mode** (e.g. nothing in `dark/` and nothing in `both/`) makes `pickNext()` return early and leaves no wallpaper at all, with no fallback. The spec does not address it. Pinned in Task 2.
5. **alacritty may not live-reload when an *imported* file changes**, as opposed to its main config, leaving open terminals on the old palette. Must be settled empirically, not by assumption. Pinned in Task 6.

---

### Task 1: Replace the dark palette in `theme-colors.nix`

**Files:**
- Modify: `modules/lib/theme-colors.nix:1-21` (header comment and the whole `dark` attrset)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `modules/lib/theme-colors.nix` with `dark` and `light` attrsets, each having keys `base00`–`base0F` whose values are 6-character uppercase hex strings **without** a leading `#`. Consumers add their own `#` and alpha prefix. This shape is unchanged from today; only the `dark` values change.

Existing consumers that pick up the new palette immediately: `modules/home-manager/display/sway/mako.nix`, `modules/home-manager/display/vicinae.nix`, the `Lock-dark.qml`/`Lock-light.qml` entries in `modules/home-manager/display/sway/quickshell/default.nix`, and `modules/nixosconf/greetd.nix` (the greeter). The quickshell **bar** still reads stylix at this point and changes in Task 3, so the desktop is intentionally inconsistent between Task 1 and Task 3.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t1.sh`:

```bash
#!/usr/bin/env bash
set -eu
cd /home/ogama/nixos-configuration
nix eval --impure --expr '
let c = import ./modules/lib/theme-colors.nix;
    want = {
      base00 = "000000"; base01 = "222222"; base02 = "444444"; base03 = "6A6A6A";
      base04 = "B5B0AA"; base05 = "FFFAF3"; base06 = "FFFCF8"; base07 = "FFFFFF";
      base08 = "FF273F"; base09 = "F1895C"; base0A = "FFB900"; base0B = "27D796";
      base0C = "00D7EB"; base0D = "008DF8"; base0E = "6C43A5"; base0F = "E95678";
    };
    bad = builtins.filter (k: c.dark.${k} != want.${k}) (builtins.attrNames want);
    lightOk = c.light.base00 == "FDF0ED" && c.light.base05 == "403C3D" && c.light.base0E == "1D8991";
in if bad == [] && lightOk
   then "PASS"
   else "FAIL dark-mismatch=[" + builtins.concatStringsSep "," bad + "] lightIntact=" + builtins.toString lightOk
' --raw
echo
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t1.sh
```

Expected: `FAIL dark-mismatch=[base00,base01,...] lightIntact=true` — every dark slot still holds its Horizon value, while the light palette is already correct.

- [ ] **Step 3: Replace the `dark` attrset and correct the header comment**

Replace lines 1–21 of `modules/lib/theme-colors.nix` (the comment block and the whole `dark = { ... };`) with:

```nix
# Two palettes, different provenance.
#
# `light` is hand-transcribed from pkgs.base16-schemes' horizon-light.yaml
# (Nix has no YAML parser).
#
# `dark` is NOT Horizon. It is the hand-picked palette that used to live in
# modules/home-manager/alacritty.nix, promoted to the system dark theme: pure
# black ground, warm off-white text, vivid accents. ANSI-16 has no equivalent
# for a base16 greyscale ramp, an orange, or a spare slot, so base03/base04/
# base06 are derived and base09/base0F reuse two values that were defined but
# never referenced in alacritty.nix's let block.
#
# Deliberate substitutions, so the palette survives being used for UI chrome
# rather than just terminal text: base08 takes the *bright* red #FF273F rather
# than normal #FF000F (near-pure red is punishing on borders and status bands),
# and base0E takes the *bright* magenta #6C43A5 rather than normal #FF00FF
# (pure fuchsia is unusable as a UI colour).
#
# base0D is the UI accent: bar clock, mako border, vicinae accent, lockscreen
# highlights. It is blue here, where Horizon put a pink-red.
#
# Update this file, not any hex literal elsewhere, if a palette changes.
{
  dark = {
    base00 = "000000"; # terminal background
    base01 = "222222"; # terminal normal black
    base02 = "444444"; # terminal bright black
    base03 = "6A6A6A"; # derived: continues the 00 -> 22 -> 44 ramp
    base04 = "B5B0AA"; # derived: dim foreground, warm-tinted to match base05
    base05 = "FFFAF3"; # terminal foreground
    base06 = "FFFCF8"; # derived
    base07 = "FFFFFF"; # terminal white
    base08 = "FF273F"; # terminal bright red
    base09 = "F1895C"; # the unused `orange` from alacritty.nix
    base0A = "FFB900"; # terminal yellow
    base0B = "27D796"; # terminal green
    base0C = "00D7EB"; # terminal cyan
    base0D = "008DF8"; # terminal blue - the UI accent
    base0E = "6C43A5"; # terminal bright magenta
    base0F = "E95678"; # the unused `red` from alacritty.nix
  };
```

Leave the `light = { ... };` attrset and the closing `}` exactly as they are.

- [ ] **Step 4: Run the test to confirm it passes**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t1.sh
```

Expected: `PASS`

- [ ] **Step 5: Confirm every consumer still evaluates, including the NixOS-side greeter**

```bash
cd /home/ogama/nixos-configuration
nix eval --impure --expr '
let f = builtins.getFlake (toString ./.);
    hm = f.homeConfigurations.personal.config;
    os = f.nixosConfigurations.personal.config;
in "mako-border=" + hm.services.mako.settings.border-color
 + " vicinae-dark-accent=" + hm.programs.vicinae.themes.horizon-dark.colors.core.accent
 + " greeter-drv-ok=" + builtins.toString (builtins.isString os.system.build.toplevel.drvPath)
' --raw
echo
```

Expected: `mako-border=#008DF8 vicinae-dark-accent=#008DF8 greeter-drv-ok=true` — the accent has become blue in both home-manager consumers, and the NixOS closure (which includes the greeter's generated QML) still evaluates.

- [ ] **Step 6: Commit**

```bash
cd /home/ogama/nixos-configuration
git add modules/lib/theme-colors.nix
git commit -m "feat(theme): promote the terminal palette to the system dark theme"
```

---

### Task 2: Split wallpapers into dark/light/both

**Files:**
- Create: `assets/wallpaper/both/` (via `git mv` of 4 existing files)
- Create: `assets/wallpaper/dark/.gitkeep`, `assets/wallpaper/light/.gitkeep`
- Modify: `modules/lib/qml-theme.nix` (add a `wallpaperDirs` argument and `@wallpaperDirs@` token)
- Modify: `modules/home-manager/display/sway/quickshell/components/Wallpaper.qml:64-70` (use the token; guard an empty pool)
- Modify: `modules/home-manager/display/sway/quickshell/default.nix` (pass `wallpaperDirs`)
- Modify: `modules/home-manager/display/i3/default.nix:87` (repoint the Nix path literal — **breaks `epita` evaluation if missed**)
- Modify: `modules/home-manager/display/sway/default.nix:14-17` (delete 4 dead variables)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `qml-theme.nix` gains the argument `wallpaperDirs ? "both"` — a **space-separated list of directory names** relative to `$HOME/nixos-configuration/assets/wallpaper`, substituted into `@wallpaperDirs@`. It is defaulted so that `modules/nixosconf/greetd.nix`, which calls `qml-theme.nix` but never renders `Wallpaper.qml`, needs no change. Task 7 passes `"dark both"` and `"light both"`; this task passes `"dark both"` for the single tree, preserving today's dark-mode behaviour.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t2.sh`:

```bash
#!/usr/bin/env bash
set -eu
cd /home/ogama/nixos-configuration
fail=0

# 2a: all four wallpapers live in both/, and the flat directory holds no images.
for f in background_monocle.png IMG-20260904-WA0008.jpg \
         wallpaper_the_lords_of_the_rings.jpeg \
         wp11126805-lord-of-the-rings-art-wallpapers.jpg; do
  [ -f "assets/wallpaper/both/$f" ] || { echo "FAIL missing both/$f"; fail=1; }
done
stray=$(find assets/wallpaper -maxdepth 1 -type f | wc -l)
[ "$stray" -eq 0 ] || { echo "FAIL $stray image(s) still flat in assets/wallpaper"; fail=1; }

# 2b: Review Focus 1 - dark/ and light/ must survive a clean checkout.
for d in dark light both; do
  [ -d "assets/wallpaper/$d" ] || { echo "FAIL missing dir $d"; fail=1; }
done
for d in dark light; do
  git ls-files --error-unmatch "assets/wallpaper/$d/.gitkeep" >/dev/null 2>&1 \
    || { echo "FAIL $d/.gitkeep not tracked by git"; fail=1; }
done

# 2c: the find command is tokenised and resolves to the two dark-mode dirs.
nix eval --impure --expr '
let f = builtins.getFlake (toString ./.);
    c = f.homeConfigurations.personal.config;
    t = builtins.replaceStrings ["\n"] [" "] c.xdg.configFile."quickshell/widgets/components/Wallpaper.qml".text;
    has = p: builtins.match (".*" + p + ".*") t != null;
in if has "find dark both" && has "assets/wallpaper" && !(has "@wallpaperDirs@")
   then "PASS-find" else "FAIL-find"
' --raw | grep -q PASS-find || { echo "FAIL find not tokenised"; fail=1; }

# 2d: Review Focus 4 - an empty pool must not leave a blank screen silently.
grep -q "imagePaths.length === 0" \
  modules/home-manager/display/sway/quickshell/components/Wallpaper.qml \
  || { echo "FAIL no empty-pool guard"; fail=1; }
grep -q "wallpaperPoolEmpty" \
  modules/home-manager/display/sway/quickshell/components/Wallpaper.qml \
  || { echo "FAIL empty pool not surfaced"; fail=1; }

# 2e: epita must still evaluate after the move.
nix eval --impure --expr '
let f = builtins.getFlake (toString ./.);
in builtins.toString (builtins.isString f.homeConfigurations.epita.config.home.activationPackage.drvPath)
' --raw | grep -q true || { echo "FAIL epita no longer evaluates"; fail=1; }

# 2f: the dead sway variables are gone.
grep -q "toString /background" modules/home-manager/display/sway/default.nix \
  && { echo "FAIL dead wallpaper vars still present"; fail=1; }

[ "$fail" -eq 0 ] && echo PASS
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t2.sh
```

Expected: failures for the missing `both/` files, missing directories, untracked `.gitkeep`s, un-tokenised `find`, missing empty-pool guard, and the still-present dead variables. `epita` should currently pass.

- [ ] **Step 3: Move the wallpapers and create the pool directories**

```bash
cd /home/ogama/nixos-configuration
mkdir -p assets/wallpaper/both assets/wallpaper/dark assets/wallpaper/light
git mv assets/wallpaper/background_monocle.png assets/wallpaper/both/
git mv assets/wallpaper/IMG-20260904-WA0008.jpg assets/wallpaper/both/
git mv assets/wallpaper/wallpaper_the_lords_of_the_rings.jpeg assets/wallpaper/both/
git mv assets/wallpaper/wp11126805-lord-of-the-rings-art-wallpapers.jpg assets/wallpaper/both/
touch assets/wallpaper/dark/.gitkeep assets/wallpaper/light/.gitkeep
git add assets/wallpaper/dark/.gitkeep assets/wallpaper/light/.gitkeep
```

`.gitkeep` is required because git does not track empty directories; without it `dark/` and `light/` would be absent from a fresh checkout and `find` would warn on every quickshell start.

- [ ] **Step 4: Repoint the i3 path literal (this is what keeps `epita` evaluating)**

In `modules/home-manager/display/i3/default.nix:87`, change:

```nix
          "feh --bg-fill ${../../../../assets/wallpaper/background_monocle.png}";
```

to:

```nix
          "feh --bg-fill ${../../../../assets/wallpaper/both/background_monocle.png}";
```

A Nix path literal must resolve at evaluation time, and `display/i3` is imported by `host/epita/epita.nix`, so a stale path breaks that profile's evaluation outright — not just its wallpaper.

- [ ] **Step 5: Delete the dead wallpaper variables**

In `modules/home-manager/display/sway/default.nix`, delete these four lines from the `let` block (lines 14–17):

```nix
  wallpeper = toString /background.png;
  wallpeper_blure = toString /background_blure.png;
  wallpaper_tache = toString /background_tache.png;

  wallpeper_monocle = toString /background_monocle.png;
```

They are absolute paths to the filesystem root that do not exist and are never referenced. `toString` on a missing path does not error, which is why they have been silently dead.

- [ ] **Step 6: Add the `wallpaperDirs` token to `qml-theme.nix`**

In `modules/lib/qml-theme.nix`, add to the argument list, immediately after the `mutedColor ? "#FF${colors.base04}"` line and before the closing `}:`:

```nix
  # Space-separated directory names under assets/wallpaper that the picker
  # draws from, substituted into Wallpaper.qml's find. Defaulted so
  # modules/nixosconf/greetd.nix, which renders no Wallpaper.qml, needs no
  # change. The quickshell module passes "dark both" or "light both".
, wallpaperDirs ? "both"
```

Then add `"@wallpaperDirs@"` to the search list and `wallpaperDirs` to the replacement list, keeping both lists in the same order. Add the search string after `"@mutedColor@"` and the replacement after the final `"#FF${colors.base05}"` entry that corresponds to it, so the positions stay aligned.

- [ ] **Step 7: Tokenise the find and guard an empty pool in `Wallpaper.qml`**

Replace the `command` array at `modules/home-manager/display/sway/quickshell/components/Wallpaper.qml:64-70` with:

```qml
        command: [
            "bash", "-c",
            "cd \"$HOME/nixos-configuration/assets/wallpaper\" && find @wallpaperDirs@ -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) -printf '%h/%f\\n' | sed \"s|^|$HOME/nixos-configuration/assets/wallpaper/|\" | sort"
        ]
```

`cd` first so the directory names stay relative and the token cannot inject an absolute path; `sed` restores absolute paths because the QML `Image` sources need them.

Then add an empty-pool guard. Add this property next to the other `property` declarations near the top of the `Scope`:

```qml
    // Review Focus 4: a mode whose pool is empty (nothing in dark/ and nothing
    // in both/) would otherwise leave no wallpaper at all and no clue why.
    property bool wallpaperPoolEmpty: root.imagePaths.length === 0
```

And in the `StdioCollector`'s `onStreamFinished`, after the existing `root.imagePaths = ...` assignment, add:

```qml
                if (root.imagePaths.length === 0)
                    console.warn("wallpaper: pool empty for dirs '@wallpaperDirs@' - add an image to assets/wallpaper/both/")
```

- [ ] **Step 8: Pass `wallpaperDirs` from the quickshell module**

In `modules/home-manager/display/sway/quickshell/default.nix`, add `wallpaperDirs = "dark both";` to the attrset passed to `qmlTheme` for `barTheme` (alongside `inherit colors laserColor systemctlBin corptaFontPath;`). Task 7 replaces this with a per-variant value; `"dark both"` preserves today's dark-mode behaviour in the meantime.

- [ ] **Step 9: Run the test to confirm it passes**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t2.sh
```

Expected: `PASS`

- [ ] **Step 10: Confirm no token leaked into any generated QML**

```bash
cd /home/ogama/nixos-configuration
nix eval --impure --expr '
let f = builtins.getFlake (toString ./.);
    c = f.homeConfigurations.personal.config;
    files = builtins.filter (n: builtins.match ".*\\.qml" n != null) (builtins.attrNames c.xdg.configFile);
    leak = n: builtins.match ".*@[a-zA-Z]+@.*" (builtins.replaceStrings ["\n"] [" "] c.xdg.configFile.${n}.text) != null;
    bad = builtins.filter leak files;
in if bad == [] then "PASS no leaked tokens" else "FAIL leaked in " + builtins.concatStringsSep "," bad
' --raw
echo
```

Expected: `PASS no leaked tokens`. This check is known to work: run against the raw source it correctly reports tokens.

- [ ] **Step 11: Commit**

```bash
cd /home/ogama/nixos-configuration
git add -A assets/wallpaper modules/lib/qml-theme.nix \
  modules/home-manager/display/sway/quickshell \
  modules/home-manager/display/i3/default.nix \
  modules/home-manager/display/sway/default.nix
git commit -m "feat(wallpaper): split into dark/light/both pools and tokenise the picker's search"
```

---

### Task 3: Point the quickshell bar at `theme-colors.nix`

**Files:**
- Modify: `modules/home-manager/display/sway/quickshell/default.nix:1-30` (the `let` block)

**Interfaces:**
- Consumes: `theme-colors.nix`'s `dark` attrset from Task 1; the `wallpaperDirs` argument from Task 2.
- Produces: `modules/home-manager/display/sway/quickshell/default.nix` with **no reference to `config.lib.stylix.colors` or `config.stylix.polarity`**. This is the last stylix colour consumer; Task 4 cannot proceed until it is gone.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t3.sh`:

```bash
#!/usr/bin/env bash
set -eu
cd /home/ogama/nixos-configuration
fail=0

grep -q "stylix" modules/home-manager/display/sway/quickshell/default.nix \
  && { echo "FAIL quickshell still references stylix"; fail=1; }

nix eval --impure --expr '
let f = builtins.getFlake (toString ./.);
    c = f.homeConfigurations.personal.config;
    t = n: builtins.replaceStrings ["\n"] [" "] c.xdg.configFile.${n}.text;
    has = n: p: builtins.match (".*" + p + ".*") (t n) != null;
    clock = "quickshell/widgets/components/Clock.qml";
    panel = "quickshell/widgets/components/StatusPanel.qml";
in if has clock "#FF008DF8"          # tempColor = base0D, the new blue accent
   && has clock "#FFFFFAF3"          # clockColor = base05, uppercase now
   && !(has clock "#FFdf5273")       # the old lowercase Horizon accent is gone
   && has panel "#FF00D7EB"          # upColor = base0C cyan
   && has panel "#FFF1895C"          # degradedColor = base09 orange
   && has panel "#FFFF273F"          # downColor = base08 red
   && has panel "#FFB5B0AA"          # mutedColor = base04
   then "PASS-colors" else "FAIL-colors"
' --raw | grep -q PASS-colors || { echo "FAIL generated bar colours wrong"; fail=1; }

[ "$fail" -eq 0 ] && echo PASS
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t3.sh
```

Expected: both checks fail — the module still references stylix, and the generated Clock.qml still carries the lowercase Horizon accent `#FFdf5273`.

- [ ] **Step 3: Replace the colour source in the `let` block**

In `modules/home-manager/display/sway/quickshell/default.nix`, replace these lines:

```nix
  colors = config.lib.stylix.colors;

  laserColor = if config.stylix.polarity == "light" then "#FFFFFF" else "#000000";
```

with:

```nix
  # The bar renders in one polarity per generated tree. Task 7 turns this into
  # a per-variant value; until then the single tree is the dark one.
  polarity = "dark";

  colors = (import ../../../../lib/theme-colors.nix).${polarity};

  laserColor = if polarity == "light" then "#FFFFFF" else "#000000";
```

Then replace:

```nix
  isLight = config.stylix.polarity == "light";
```

with:

```nix
  isLight = polarity == "light";
```

Leave the `statusColors` attrset's bodies alone — the measured light values and the dark values are still selected by `isLight`, which now reads the local `polarity`. Also leave `lockThemeColors` as it is; it already imports `theme-colors.nix` directly.

- [ ] **Step 4: Update the stale comment about the colour source**

The comment at `modules/home-manager/display/sway/quickshell/default.nix:47-51` says the lock theming is keyed off the shared palette "instead of `config.lib.stylix.colors`". That distinction no longer exists — both now come from `theme-colors.nix`. Replace that sentence so it reads:

```nix
  # Lockscreen-only theming - reuses the same @token@ substitution the file
  # already uses for the bar, and the same shared palette, but scoped to just
  # the lock component and with each variant's own artwork. Do not extend this
  # to shell.qml/Wallpaper/Clock/Music/Calendar/RevealMask/LaserBar - those are
  # the in-progress bar.
```

- [ ] **Step 5: Run the test to confirm it passes**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t3.sh
```

Expected: `PASS`

- [ ] **Step 6: Commit**

```bash
cd /home/ogama/nixos-configuration
git add modules/home-manager/display/sway/quickshell/default.nix
git commit -m "refactor(quickshell): read the bar palette from theme-colors.nix, not stylix"
```

---

### Task 4: Remove stylix

**Files:**
- Delete: `modules/home-manager/stylix.nix`
- Modify: `host/personal/home.nix:18` (drop the import)
- Modify: `modules/home-manager/firefox.nix:76-82` (drop both `stylix.targets` blocks)
- Modify: `modules/home-manager/display/sway/mako.nix:13-14` (replace the stylix font reference)
- Modify: `flake.nix:17-18,36,112` (drop the input, the `follows`, the function argument, the module)

**Interfaces:**
- Consumes: Task 3 must be complete — no module may reference a stylix option.
- Produces: a tree where `grep -rn stylix --include=*.nix` finds nothing. `flake.lock` shrinks; commit it.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t4.sh`:

```bash
#!/usr/bin/env bash
set -eu
cd /home/ogama/nixos-configuration
fail=0

hits=$(grep -rn "stylix" --include="*.nix" . | grep -v "^./docs" || true)
[ -z "$hits" ] || { echo "FAIL stylix still referenced:"; echo "$hits"; fail=1; }
[ -f modules/home-manager/stylix.nix ] && { echo "FAIL stylix.nix still exists"; fail=1; }
grep -q "stylix" flake.lock && { echo "FAIL stylix still in flake.lock"; fail=1; }

# mako keeps a font, now a literal.
nix eval --impure --expr '
let f = builtins.getFlake (toString ./.);
in f.homeConfigurations.personal.config.services.mako.settings.font
' --raw | grep -q "Inter 14" || { echo "FAIL mako font wrong"; fail=1; }

# All four profiles must still evaluate.
for p in personal oserv epita epita-light; do
  nix eval --impure --expr "
let f = builtins.getFlake (toString ./.);
in builtins.toString (builtins.isString f.homeConfigurations.\"$p\".config.home.activationPackage.drvPath)
" --raw | grep -q true || { echo "FAIL profile $p no longer evaluates"; fail=1; }
done

[ "$fail" -eq 0 ] && echo PASS
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t4.sh
```

Expected: stylix is still referenced in `flake.nix`, `firefox.nix`, `mako.nix`, `host/personal/home.nix`, and `stylix.nix` itself still exists.

- [ ] **Step 3: Replace the stylix font reference in mako**

In `modules/home-manager/display/sway/mako.nix`, replace:

```nix
      font =
        "${config.stylix.fonts.sansSerif.name} ${toString config.stylix.fonts.sizes.popups}";
```

with:

```nix
      # Was config.stylix.fonts.sansSerif.name + sizes.popups; these are the
      # values stylix supplied. display/font.nix installs Inter.
      font = "Inter 14";
```

`config` may now be unused in this file's argument list. If `nix flake check` warns about it, leave the argument — other attrs may still use it; check before removing.

- [ ] **Step 4: Drop the stylix target blocks from firefox.nix**

In `modules/home-manager/firefox.nix`, delete:

```nix
  stylix.targets.firefox = {
    enable = false;
    profileNames = [ "default" ];
  };
  stylix.targets.zen-browser = {
    # enable = false;
    profileNames = [ "default" ];
  };
```

Nothing replaces them. `firefox.nix:112` already sets `zen.view.window.scheme = 2` (auto), which is what makes zen follow light/dark; stylix's generated userChrome was overriding it.

- [ ] **Step 5: Delete the module and its import**

```bash
cd /home/ogama/nixos-configuration
git rm modules/home-manager/stylix.nix
```

Then remove this line from `host/personal/home.nix`:

```nix
    ../../modules/home-manager/stylix.nix
```

- [ ] **Step 6: Remove the flake input**

In `flake.nix`, delete these two lines from `inputs`:

```nix
    stylix.url = "github:nix-community/stylix/release-26.05";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
```

Remove `stylix,` from the outputs function's argument list (around line 36). Then remove this line from the `personal` homeConfiguration's `modules` list (around line 112):

```nix
            stylix.homeModules.stylix
```

- [ ] **Step 7: Refresh the lockfile and run the test**

```bash
cd /home/ogama/nixos-configuration
nix flake lock
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t4.sh
```

Expected: `PASS`

- [ ] **Step 8: Run the flake check**

```bash
cd /home/ogama/nixos-configuration
nix flake check 2>&1 | tail -20
```

Expected: no errors. Remember this does not validate the generated QML.

- [ ] **Step 9: Commit**

```bash
cd /home/ogama/nixos-configuration
git add -A flake.nix flake.lock host/personal/home.nix \
  modules/home-manager/firefox.nix modules/home-manager/display/sway/mako.nix
git commit -m "feat: drop stylix entirely"
```

---

### Task 5: GTK light/dark at runtime

**Files:**
- Modify: `modules/home-manager/display/gtk.nix`
- Modify: `modules/home-manager/darkman.nix:55-80` (extend both `gtk-theme` scripts)

**Interfaces:**
- Consumes: Task 4 — stylix must no longer be setting `gtk.theme`/`gtk.iconTheme`.
- Produces: `services.darkman.darkModeScripts.gtk-theme` and `.lightModeScripts.gtk-theme` each writing three dconf keys. No new Nix-level interface.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t5.sh`:

```bash
#!/usr/bin/env bash
set -eu
cd /home/ogama/nixos-configuration
nix eval --impure --expr '
let f = builtins.getFlake (toString ./.);
    c = f.homeConfigurations.personal.config;
    d = c.services.darkman.darkModeScripts.gtk-theme;
    l = c.services.darkman.lightModeScripts.gtk-theme;
    has = s: p: builtins.match (".*" + p + ".*") (builtins.replaceStrings ["\n"] [" "] s) != null;
    pkgNames = map (p: p.name or "") c.home.packages;
    hasPkg = n: builtins.any (p: builtins.match (".*" + n + ".*") p != null) pkgNames;
in if has d "prefer-dark" && has d "adw-gtk3-dark" && has d "Papirus-Dark"
   && has l "prefer-light" && has l "adw-gtk3" && has l "Papirus-Light"
   && hasPkg "adw-gtk3" && hasPkg "papirus-icon-theme"
   # Review Focus 2: home-manager must NOT manage these, or activation stomps
   # whatever mode darkman last selected.
   && c.gtk.theme == null && c.gtk.iconTheme == null
   then "PASS"
   else "FAIL dark-ok=" + builtins.toString (has d "adw-gtk3-dark")
      + " light-ok=" + builtins.toString (has l "Papirus-Light")
      + " pkgs-ok=" + builtins.toString (hasPkg "adw-gtk3" && hasPkg "papirus-icon-theme")
      + " hm-not-managing=" + builtins.toString (c.gtk.theme == null && c.gtk.iconTheme == null)
' --raw
echo
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t5.sh
```

Expected: `FAIL dark-ok=false light-ok=false pkgs-ok=false hm-not-managing=true` — the scripts only write `color-scheme`, and the theme packages are not installed (they came from stylix).

- [ ] **Step 3: Install the theme packages**

In `modules/home-manager/display/gtk.nix`, replace:

```nix
  home.packages = with pkgs; [ dconf ];
```

with:

```nix
  # The themes must exist on disk, but are deliberately NOT declared via
  # gtk.theme / gtk.iconTheme: home-manager's gtk module writes both
  # gtk-3.0/settings.ini and the dconf keys, so every activation would stomp
  # whatever mode darkman last selected. darkman owns all three keys
  # (color-scheme, gtk-theme, icon-theme) - see modules/home-manager/darkman.nix.
  home.packages = with pkgs; [
    dconf
    adw-gtk3
    papirus-icon-theme
  ];
```

- [ ] **Step 4: Extend both darkman gtk scripts**

In `modules/home-manager/darkman.nix`, replace the `gtk-theme` entry in `darkModeScripts`:

```nix
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
      '';
```

with:

```nix
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
        ${dconfExe} write /org/gnome/desktop/interface/gtk-theme "'adw-gtk3-dark'"
        ${dconfExe} write /org/gnome/desktop/interface/icon-theme "'Papirus-Dark'"
      '';
```

and the `lightModeScripts` counterpart with:

```nix
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
        ${dconfExe} write /org/gnome/desktop/interface/gtk-theme "'adw-gtk3'"
        ${dconfExe} write /org/gnome/desktop/interface/icon-theme "'Papirus-Light'"
      '';
```

Theme names verified present in the store: `adw-gtk3` ships `adw-gtk3` and `adw-gtk3-dark`; `papirus-icon-theme` ships `Papirus`, `Papirus-Dark` and `Papirus-Light`.

- [ ] **Step 5: Run the test to confirm it passes**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t5.sh
```

Expected: `PASS`

- [ ] **Step 6: Commit**

```bash
cd /home/ogama/nixos-configuration
git add modules/home-manager/display/gtk.nix modules/home-manager/darkman.nix
git commit -m "feat(gtk): switch theme and icons with darkman instead of pinning them"
```

---

### Task 6: alacritty dark/light with live reload

**Files:**
- Create: `modules/lib/alacritty-colors.nix` (both colour variants, shared by the two modules below)
- Modify: `modules/home-manager/alacritty.nix` (move colours out, declare the import, seed on activation)
- Modify: `modules/home-manager/darkman.nix` (add an `alacritty` script to both script sets)

**Interfaces:**
- Consumes: Task 1's palette only for documentation purposes — the dark variant is a **verbatim** copy of today's colours, not derived from base16.
- Produces: `modules/lib/alacritty-colors.nix`, a function `{ pkgs }: { dark = <derivation>; light = <derivation>; }` where each value is a `pkgs.writeText` TOML colour file. Both `alacritty.nix` and `darkman.nix` import it, following the same shared-`modules/lib/` convention as `theme-colors.nix` and `qml-theme.nix`. `~/.config/alacritty/colors.toml` is a plain file seeded by `home.activation.alacrittyColorsDefault`, never managed by `xdg.configFile`.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t6.sh`:

```bash
#!/usr/bin/env bash
set -eu
cd /home/ogama/nixos-configuration
fail=0

nix eval --impure --expr '
let f = builtins.getFlake (toString ./.);
    c = f.homeConfigurations.personal.config;
    s = c.programs.alacritty.settings;
    d = c.services.darkman.darkModeScripts.alacritty or "";
    l = c.services.darkman.lightModeScripts.alacritty or "";
    has = x: p: builtins.match (".*" + p + ".*") (builtins.replaceStrings ["\n"] [" "] x) != null;
in if !(s ? colors)                                  # colours moved out
   && (s.general.import or []) != []                 # import declared
   && has d "colors.toml" && has l "colors.toml"     # both scripts write it
   # Review Focus 2: the rewritten file must not be home-manager-managed.
   && !(c.xdg.configFile ? "alacritty/colors.toml")
   && (c.home.activation ? alacrittyColorsDefault)   # seeded on activation
   then "PASS-nix"
   else "FAIL-nix colors-moved=" + builtins.toString (!(s ? colors))
      + " import=" + builtins.toString ((s.general.import or []) != [])
      + " scripts=" + builtins.toString (has d "colors.toml" && has l "colors.toml")
      + " unmanaged=" + builtins.toString (!(c.xdg.configFile ? "alacritty/colors.toml"))
      + " seeded=" + builtins.toString (c.home.activation ? alacrittyColorsDefault)
' --raw | grep -q PASS-nix || { echo "FAIL nix-level alacritty wiring"; fail=1; }

# The dark variant must be today's palette, verbatim.
L=modules/lib/alacritty-colors.nix
grep -q '#000000' $L || { echo "FAIL dark bg changed"; fail=1; }
grep -q '#fffaf3' $L || { echo "FAIL dark fg changed"; fail=1; }
grep -q '#ff000f' $L || { echo "FAIL dark normal red lost"; fail=1; }
grep -q '#FF00FF' $L || { echo "FAIL dark normal magenta lost"; fail=1; }
# The light variant must use the hand-tuned accents, not the raw base16 slots.
grep -q '#846200' $L || { echo "FAIL light yellow not hand-tuned"; fail=1; }
grep -q '#15666C' $L || { echo "FAIL light cyan not hand-tuned"; fail=1; }
grep -q '#FBE0D9' $L && { echo "FAIL raw base0A used as light yellow"; fail=1; }

[ "$fail" -eq 0 ] && echo PASS
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t6.sh
```

Expected: the nix-level wiring check fails (colours still inline, no import, no scripts), and the hand-tuned light values are absent.

- [ ] **Step 3: Create `modules/lib/alacritty-colors.nix`**

Both `alacritty.nix` and `darkman.nix` need these two derivations, so they live
in `modules/lib/` beside `theme-colors.nix` and `qml-theme.nix` rather than
being passed between modules.

```nix
# The two alacritty colour files darkman swaps between at runtime. Imported by
# modules/home-manager/alacritty.nix (to seed the default and declare the
# import) and by modules/home-manager/darkman.nix (to install the right one on
# each sunrise/sunset).
#
# `dark` is this machine's long-standing hand-picked palette, preserved
# verbatim. modules/lib/theme-colors.nix' dark palette was derived FROM these
# values, but deliberately drops normal red (#ff000f) and normal magenta
# (#FF00FF) as too harsh for UI chrome - the terminal keeps its full original
# ANSI set, so this is written out rather than generated from base16.
#
# `light` keeps Horizon light's background and foreground but uses hand-tuned
# ANSI accents. The naive base16 mapping is unusable: base0A ("yellow") is
# #FBE0D9, which measures 1.13:1 against the #FDF0ED ground - invisible - while
# base0D ("blue") is a crimson and base0C ("cyan") a red-orange, so both would
# read red. Every value below was measured against #FDF0ED and clears the 4.5:1
# text floor; ratios are in the comments. "Bright" is *darker* here, because on
# a light ground more emphasis means more contrast.
#
# Light cyan is #15666C, not the #1D8991 used for the status widget's light
# upColor: that value is a filled band against a 3:1 floor and measures only
# 3.74:1 as text. Same hue, different floor - not an inconsistency.
{ pkgs }:
{
  dark = pkgs.writeText "alacritty-colors-dark.toml" ''
    [colors.primary]
    background = "#000000"
    foreground = "#fffaf3"

    [colors.normal]
    black   = "#222222"
    red     = "#ff000f"
    green   = "#27d796"
    yellow  = "#ffb900"
    blue    = "#008df8"
    magenta = "#FF00FF"
    cyan    = "#00d7eb"
    white   = "#ffffff"

    [colors.bright]
    black   = "#444444"
    red     = "#ff273f"
    green   = "#abe05a"
    yellow  = "#ffd141"
    blue    = "#0092ff"
    magenta = "#6c43a5"
    cyan    = "#67ffef"
    white   = "#ffffff"
  '';

  light = pkgs.writeText "alacritty-colors-light.toml" ''
    [colors.primary]
    background = "#FDF0ED"
    foreground = "#403C3D"

    [colors.normal]
    black   = "#201C1D"  # 15.1:1
    red     = "#C5283D"  # 5.0:1
    green   = "#2D7D46"  # 4.6:1
    yellow  = "#846200"  # 5.1:1
    blue    = "#1E5FA8"  # 5.8:1
    magenta = "#7B3FA0"  # 6.2:1
    cyan    = "#15666C"  # 6.0:1
    white   = "#403C3D"  # 9.8:1

    [colors.bright]
    black   = "#6B6466"
    red     = "#A61E30"
    green   = "#226336"
    yellow  = "#6B4F00"
    blue    = "#174B85"
    magenta = "#633280"
    cyan    = "#105055"
    white   = "#201C1D"
  '';
}
```

- [ ] **Step 4: Rewrite `alacritty.nix`**

Replace the entire contents of `modules/home-manager/alacritty.nix` with:

```nix
{ pkgs, lib, config, ... }:
let
  colorsPath = "${config.xdg.configHome}/alacritty/colors.toml";
  alacrittyColors = import ../lib/alacritty-colors.nix { inherit pkgs; };
in
{
  programs.alacritty = {
    enable = true;

    settings = {
      general = {
        # colors.toml is rewritten at runtime by darkman and so must NOT be
        # managed by xdg.configFile - a managed path is a read-only store
        # symlink. It is seeded by the activation script below, following the
        # same pattern as darkmanTimezoneSync.
        import = [ colorsPath ];
        live_config_reload = true;
      };

      window = { decorations = "buttonless"; };

      font = {
        size = 13.5;
        normal.family = "JetBrainsMonoNerdFont";
        bold.family = "JetBrainsMonoNerdFont";
        italic.family = "JetBrainsMonoNerdFont";
      };

      terminal.shell = { program = "fish"; };
    };
  };

  home.activation.alacrittyColorsDefault =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${pkgs.coreutils}/bin/mkdir -p "${config.xdg.configHome}/alacritty"
      run ${pkgs.coreutils}/bin/install -m 644 ${alacrittyColors.dark} "${colorsPath}"
    '';
}
```

`install -m 644`, not `cp`: the store file is read-only, and `cp` would carry
those permissions over, leaving a file darkman cannot overwrite.

Note the old `let` block's `green`/`yellow`/`orange`/`red` bindings disappear
with this rewrite. Two of them (`orange = "#f1895c"`, `red = "#e95678"`) were
never referenced and now live on as `base09`/`base0F` in `theme-colors.nix`
(Task 1).

- [ ] **Step 5: Add the darkman scripts**

In `modules/home-manager/darkman.nix`, add to the `let` block:

```nix
  alacrittyColorsPath = "${config.xdg.configHome}/alacritty/colors.toml";
  alacrittyColors = import ../lib/alacritty-colors.nix { inherit pkgs; };
```

Add to `darkModeScripts`:

```nix
      alacritty = ''
        ${coreutils}/bin/install -m 644 ${alacrittyColors.dark} "${alacrittyColorsPath}"
      '';
```

and to `lightModeScripts`:

```nix
      alacritty = ''
        ${coreutils}/bin/install -m 644 ${alacrittyColors.light} "${alacrittyColorsPath}"
      '';
```

`install` writes new content at that path, which is what alacritty's watcher keys on. Do **not** symlink: re-pointing a symlink may not fire inotify.

- [ ] **Step 6: Run the test to confirm it passes**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t6.sh
```

Expected: `PASS`

- [ ] **Step 7: Settle Review Focus 5 empirically**

This is the one behaviour that cannot be established by reading. After Task 8's switch, with a terminal already open:

```bash
darkman set light
# watch the OPEN terminal
darkman set dark
```

Record which of these happened:
- **Open terminals repaint** — imported-file watching works; nothing more to do.
- **Only newly opened terminals change** — accepted fallback; alacritty exposes no reload signal. Add a comment in `alacritty.nix` recording the finding so nobody re-litigates it.

Do not alter the design before observing this.

- [ ] **Step 8: Commit**

```bash
cd /home/ogama/nixos-configuration
git add modules/lib/alacritty-colors.nix modules/home-manager/alacritty.nix \
        modules/home-manager/darkman.nix
git commit -m "feat(alacritty): dark/light colour variants switched by darkman"
```

---

### Task 7: Generate two quickshell trees and flip between them

**Files:**
- Modify: `modules/home-manager/display/sway/quickshell/default.nix` (generate both trees; replace the lock symlink machinery)
- Modify: `modules/home-manager/darkman.nix` (replace the two `quickshell-lock-theme` scripts with one tree flip; fix `entryAfter`)

**Interfaces:**
- Consumes: Task 2's `wallpaperDirs` token, Task 3's local `polarity`.
- Produces: `~/.config/quickshell/widgets` as a symlink to `widgets-dark` or `widgets-light`, created by `home.activation.quickshellThemeTree`. The activation entry `quickshellLockDefault` **ceases to exist** — `darkmanTimezoneSync`'s `entryAfter` must be updated in the same change.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t7.sh`:

```bash
#!/usr/bin/env bash
set -eu
cd /home/ogama/nixos-configuration
nix eval --impure --expr '
let f = builtins.getFlake (toString ./.);
    c = f.homeConfigurations.personal.config;
    cf = c.xdg.configFile;
    t = n: builtins.replaceStrings ["\n"] [" "] cf.${n}.text;
    has = n: p: builtins.match (".*" + p + ".*") (t n) != null;
    hasK = n: cf ? ${n};
    dScript = c.services.darkman.darkModeScripts.quickshell-theme or "";
    lScript = c.services.darkman.lightModeScripts.quickshell-theme or "";
    hasS = x: p: builtins.match (".*" + p + ".*") (builtins.replaceStrings ["\n"] [" "] x) != null;
    qmlFiles = builtins.filter (n: builtins.match ".*\\.qml" n != null) (builtins.attrNames cf);
    leak = n: builtins.match ".*@[a-zA-Z]+@.*" (t n) != null;
in if
   # Both trees exist, with their own Lock.qml and cava.conf.
   hasK "quickshell/widgets-dark/shell.qml"
   && hasK "quickshell/widgets-light/shell.qml"
   && hasK "quickshell/widgets-dark/components/Lock.qml"
   && hasK "quickshell/widgets-light/components/Lock.qml"
   && hasK "quickshell/widgets-dark/cava.conf"
   && hasK "quickshell/widgets-light/cava.conf"
   # The old single tree and the Lock variant files are gone.
   && !(hasK "quickshell/widgets/shell.qml")
   && !(hasK "quickshell/widgets/components/Lock-dark.qml")
   && !(hasK "quickshell/widgets/components/Lock-light.qml")
   # Each tree carries its own palette and its own wallpaper pool.
   && has "quickshell/widgets-dark/components/Clock.qml" "#FF008DF8"
   && has "quickshell/widgets-light/components/Clock.qml" "#FFDA103F"
   && has "quickshell/widgets-dark/components/Wallpaper.qml" "find dark both"
   && has "quickshell/widgets-light/components/Wallpaper.qml" "find light both"
   # Each tree uses its own measured status colours.
   && has "quickshell/widgets-dark/components/StatusPanel.qml" "#FF00D7EB"
   && has "quickshell/widgets-light/components/StatusPanel.qml" "#FF1D8991"
   # No token survived substitution in either tree.
   && builtins.filter leak qmlFiles == []
   # Review Focus 2 + 3: the flip target is unmanaged, the activation entry
   # was renamed, and nothing still references the deleted entry.
   && !(hasK "quickshell/widgets")
   && (c.home.activation ? quickshellThemeTree)
   && !(c.home.activation ? quickshellLockDefault)
   && hasS dScript "widgets-dark" && hasS dScript "restart"
   && hasS lScript "widgets-light" && hasS lScript "restart"
   # The dangling dependency lives in the dag entry's `after` list, not in its
   # `data` script text - checking `data` would never catch it.
   && !(builtins.elem "quickshellLockDefault" c.home.activation.darkmanTimezoneSync.after)
   && builtins.elem "quickshellThemeTree" c.home.activation.darkmanTimezoneSync.after
   then "PASS" else "FAIL"
' --raw
echo
grep -rn "quickshellLockDefault\|quickshell-lock-theme" modules/ && echo "FAIL stale references above" || echo "no stale references"
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t7.sh
```

Expected: `FAIL`, plus stale references to `quickshellLockDefault` and `quickshell-lock-theme`.

- [ ] **Step 3: Generate both trees in `quickshell/default.nix`**

Replace the `let` block's theme plumbing so each variant gets its own
substitution. Replace the `polarity`/`colors`/`laserColor`/`isLight`/`statusColors`
section introduced in Task 3 with a function over the variant:

```nix
  allColors = import ../../../../lib/theme-colors.nix;

  # Horizon light puts teal at base0E where the dark palette has it at base0C,
  # and several light slots fail contrast floors against the light ground, so
  # the status colours cannot be one base16 slot for both variants. The light
  # values are measured; see the comments on each.
  statusColorsFor = variant:
    if variant == "light" then {
      # Measured against the composited light panel ground (#EBDFDC).
      upColor = "#FF1D8991";       # the darker teal, clears 3:1 as a filled band
      degradedColor = "#FFC2490B"; # base09 #F6661E is only 2.4:1; darkened to 3.8:1
      downColor = "#FFDA103F";
      mutedColor = "#CC${allColors.light.base05}"; # base04 is 2.5:1 at 11px; this is 4.9:1
    } else {
      # Measured against the new dark ground: base00 is pure black, so the
      # worst case (a white wallpaper through 10%) is about #1A1A1A, and the
      # straight slot values all clear their floors with margin.
      upColor = "#FF${allColors.dark.base0C}";       # cyan, 9.9:1
      degradedColor = "#FF${allColors.dark.base09}"; # orange, 7.0:1
      downColor = "#FF${allColors.dark.base08}";     # red, 4.7:1
      mutedColor = "#FF${allColors.dark.base04}";    # 8.1:1
    };

  themeFor = variant: qmlTheme ({
    colors = allColors.${variant};
    laserColor = if variant == "light" then "#FFFFFF" else "#000000";
    wallpaperDirs = "${variant} both";
    inherit systemctlBin corptaFontPath statusApiUrl metricsApiUrl;
    lockscreenImage = "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png";
  } // statusColorsFor variant);

  themedQmlFile = variant: path: {
    text = themeFor variant (builtins.readFile path);
  };
```

Keep `lockVariant` as it is — it already takes a variant and its own artwork.

Then replace the whole `xdg.configFile` attrset with one generated per variant:

```nix
  xdg.configFile =
    let
      cavaConf = ''
        [general]
        bars = 20
        framerate = 60
        sensitivity = 195

        [input]
        method = pipewire
        source = auto

        [smoothing]
        noise_reduction = 30

        [output]
        method = raw
        raw_target = /dev/stdout
        data_format = ascii
        ascii_max_range = 100
        bar_delimiter = 59
        frame_delimiter = 10
      '';

      lockFor = {
        dark = lockVariant "dark" ./components/LockDark.qml
          "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/dark-lockscreen-arcane-jinx.jpeg";
        light = lockVariant "light" ./components/LockLight.qml
          "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png";
      };

      # Music.qml resolves cava as Quickshell.shellDir + "/cava.conf", so each
      # tree needs its own copy; shellDir makes that automatic.
      treeFor = variant:
        let d = "quickshell/widgets-${variant}"; in {
          "${d}/cava.conf".text = cavaConf;
          "${d}/shell.qml" = themedQmlFile variant ./shell.qml;
          "${d}/components/Lock.qml" = lockFor.${variant};
          "${d}/components/Wallpaper.qml" = themedQmlFile variant ./components/Wallpaper.qml;
          "${d}/components/Clock.qml" = themedQmlFile variant ./components/Clock.qml;
          "${d}/components/Music.qml" = themedQmlFile variant ./components/Music.qml;
          "${d}/components/Calendar.qml" = themedQmlFile variant ./components/Calendar.qml;
          "${d}/components/RevealMask.qml" = themedQmlFile variant ./components/RevealMask.qml;
          "${d}/components/GlassPill.qml" = themedQmlFile variant ./components/GlassPill.qml;
          "${d}/components/ColorUtils.qml" = themedQmlFile variant ./components/ColorUtils.qml;
          "${d}/components/BeamSide.qml" = themedQmlFile variant ./components/BeamSide.qml;
          "${d}/components/CollisionEffects.qml" = themedQmlFile variant ./components/CollisionEffects.qml;
          "${d}/components/ClockModule.qml" = themedQmlFile variant ./components/ClockModule.qml;
          "${d}/components/LaserBar.qml" = themedQmlFile variant ./components/LaserBar.qml;
          "${d}/components/StatusModel.qml" = themedQmlFile variant ./components/StatusModel.qml;
          "${d}/components/Sparkline.qml" = themedQmlFile variant ./components/Sparkline.qml;
          "${d}/components/StatusPanel.qml" = themedQmlFile variant ./components/StatusPanel.qml;
        };
    in
    treeFor "dark" // treeFor "light";
```

Note `components/Lock.qml` is now a real file in each tree, so `shell.qml`'s
`Lock {}` resolves without any symlink.

- [ ] **Step 4: Replace the lock symlink activation with a tree symlink**

In the same file, replace:

```nix
  home.activation.quickshellLockDefault = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/quickshell/widgets/components/Lock-dark.qml" "${config.xdg.configHome}/quickshell/widgets/components/Lock.qml"
  '';
```

with:

```nix
  # `quickshell -c widgets` resolves through this symlink, which darkman
  # repoints on every sunrise/sunset. It must NOT be an xdg.configFile entry:
  # that would make it a read-only store symlink darkman could not replace.
  # Seeded to the dark tree; darkman corrects it on its next run.
  home.activation.quickshellThemeTree = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.coreutils}/bin/ln -sfn "${config.xdg.configHome}/quickshell/widgets-dark" "${config.xdg.configHome}/quickshell/widgets"
  '';
```

`-n` matters: without it, a second run would create
`widgets/widgets-dark` inside the existing symlinked directory instead of
replacing the link.

- [ ] **Step 5: Replace the darkman lock scripts with a tree flip, and fix `entryAfter`**

In `modules/home-manager/darkman.nix`, delete the `quickshell-lock-theme` entry
from **both** `darkModeScripts` and `lightModeScripts`, and add in their place:

```nix
      quickshell-theme = ''
        ${coreutils}/bin/ln -sfn "${config.xdg.configHome}/quickshell/widgets-dark" "${config.xdg.configHome}/quickshell/widgets"
        ${pkgs.systemd}/bin/systemctl --user restart quickshell-widgets.service || true
      '';
```

and the light counterpart with `widgets-light`. The `|| true` matches the
existing convention in `syncScript` and keeps a failed restart (no graphical
session yet) from failing the whole darkman run.

Then fix the dangling activation dependency. Replace:

```nix
  home.activation.darkmanTimezoneSync = lib.hm.dag.entryAfter [ "linkGeneration" "quickshellLockDefault" ] ''
```

with:

```nix
  home.activation.darkmanTimezoneSync = lib.hm.dag.entryAfter [ "linkGeneration" "quickshellThemeTree" ] ''
```

`quickshellLockDefault` no longer exists; leaving it referenced breaks activation.

- [ ] **Step 6: Run the test to confirm it passes**

```bash
bash /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/t7.sh
```

Expected: `PASS` and `no stale references`.

- [ ] **Step 7: Confirm the two trees really differ, and that both are complete**

```bash
cd /home/ogama/nixos-configuration
nix eval --impure --expr '
let f = builtins.getFlake (toString ./.);
    cf = f.homeConfigurations.personal.config.xdg.configFile;
    names = builtins.attrNames cf;
    stripPrefix = pre: builtins.filter (n: n != null)
      (map (n: let m = builtins.match ("quickshell/widgets-" + pre + "/(.*)") n;
                in if m == null then null else builtins.head m) names);
    d = stripPrefix "dark";
    l = stripPrefix "light";
    sortedEq = builtins.sort (a: b: a < b) d == builtins.sort (a: b: a < b) l;
in "dark-files=" + builtins.toString (builtins.length d)
 + " light-files=" + builtins.toString (builtins.length l)
 + " same-shape=" + builtins.toString sortedEq
 + " clock-differs=" + builtins.toString (
     cf."quickshell/widgets-dark/components/Clock.qml".text
     != cf."quickshell/widgets-light/components/Clock.qml".text)
' --raw
echo
```

Expected: `dark-files=17 light-files=17 same-shape=true clock-differs=true`.
A mismatched count means a file was added to one tree's `treeFor` and not the
other.

- [ ] **Step 8: Commit**

```bash
cd /home/ogama/nixos-configuration
git add modules/home-manager/display/sway/quickshell/default.nix \
        modules/home-manager/darkman.nix
git commit -m "feat(quickshell): generate dark and light trees and flip them with darkman"
```

---

### Task 8: Whole-system verification

**Files:**
- Modify: `modules/home-manager/alacritty.nix` (only to record the Step 4 finding)
- Modify: `CLAUDE.md` (drop the stale stylix mention, if any)

**Interfaces:**
- Consumes: every prior task.
- Produces: no code. This task exists because `nix flake check` cannot validate
  generated QML, so the design is not known to work until it runs.

- [ ] **Step 1: Static checks across every profile**

```bash
cd /home/ogama/nixos-configuration
nix flake check 2>&1 | tail -20
for p in personal oserv epita epita-light; do
  printf '%s: ' "$p"
  nix build --no-link ".#homeConfigurations.$p.activationPackage" 2>&1 \
    && echo OK || echo BROKEN
done
nix build --no-link .#nixosConfigurations.personal.config.system.build.toplevel 2>&1 \
  && echo "nixos personal: OK" || echo "nixos personal: BROKEN"
```

Expected: the flake check is clean and all five build. `epita` is the one that
would catch a stale wallpaper path literal; the NixOS build is what covers the
greeter's generated QML.

- [ ] **Step 2: Confirm stylix is gone from the whole tree**

```bash
cd /home/ogama/nixos-configuration
grep -rn "stylix" --include="*.nix" --include="*.qml" --include="*.md" . \
  | grep -v "^./docs/superpowers/" || echo "no stylix references outside the spec/plan"
```

Expected: only the spec and plan mention it. If `CLAUDE.md` names stylix as a
module, update that line — it is the file future sessions read first.

- [ ] **Step 3: Ask the user before switching**

Do not run the switch unprompted. Ask:

> "All static checks pass. Ready to `home-manager switch --flake .#personal`?
> The greeter also changed, which needs `sudo nixos-rebuild switch --flake
> .#personal` — shall I do both?"

Wait for an explicit yes. The home-manager switch alone will not update the
greeter, because that is a NixOS-side surface.

- [ ] **Step 4: Switch, then force a full round trip**

```bash
nix run nixpkgs#home-manager -- switch --flake .#personal
```

Then, with at least one terminal, one GTK app (e.g. nautilus or a file dialog),
and the bar visible:

```bash
darkman set light
sleep 3
darkman set dark
```

Check each surface actually flipped, and record anything that did not:

- [ ] GTK window chrome follows, and icons change (`Papirus-Light` vs `Papirus-Dark`)
- [ ] alacritty: **an already-open window** — this settles Review Focus 5
- [ ] alacritty: a newly opened window
- [ ] helix/bat inside the terminal follow the terminal's colours
- [ ] the quickshell bar and widgets repaint in the other palette
- [ ] the lockscreen shows the right variant and artwork (`Mod`-lock, then unlock)
- [ ] mako: `notify-send test` in each mode
- [ ] vicinae (`Mod+d`) follows
- [ ] zen-browser follows

Record the alacritty open-window result as a comment in `alacritty.nix` per
Task 6 Step 6, so it is not re-investigated later.

- [ ] **Step 5: Confirm the new dark palette landed, not Horizon**

In dark mode, the bar clock accent, mako's border and vicinae's accent should
all read blue `#008DF8`, where they used to be pink-red. The terminal's own
ANSI colours should look unchanged from before this work.

```bash
dconf read /org/gnome/desktop/interface/gtk-theme
dconf read /org/gnome/desktop/interface/icon-theme
dconf read /org/gnome/desktop/interface/color-scheme
```

Expected in dark mode: `'adw-gtk3-dark'`, `'Papirus-Dark'`, `'prefer-dark'`.

- [ ] **Step 6: Wallpaper pools**

```bash
# Both modes should list only both/ contents initially.
ls ~/nixos-configuration/assets/wallpaper/both/
```

Open the picker with `Mod+w` in each mode and confirm the listing. Then test
mode-specific pools:

```bash
cp ~/nixos-configuration/assets/wallpaper/both/background_monocle.png \
   ~/nixos-configuration/assets/wallpaper/dark/probe.png
darkman set dark && sleep 2   # picker should now offer probe.png
darkman set light && sleep 2  # picker should NOT offer it
rm ~/nixos-configuration/assets/wallpaper/dark/probe.png
```

Note the copy goes into the working tree, so `git status` will show it until
removed. Do not commit it.

- [ ] **Step 7: Check the logs are clean**

```bash
journalctl --user -u quickshell-widgets --since "10 minutes ago" --no-pager | tail -40
```

Expected: no QML errors, and specifically **no** `find: ... No such file or
directory` (Review Focus 1) and no `wallpaper: pool empty` warning
(Review Focus 4).

- [ ] **Step 8: Verify the greeter separately**

The greeter renders from `theme-colors.nix` through `greetd.nix`, so it changed
with the palette — but a home-manager switch does not touch it. Follow
`docs/greeter.md`'s no-reboot preview (mock proxy plus headless sway plus
`grim`) rather than rebooting to find out.

- [ ] **Step 9: Commit any findings**

```bash
cd /home/ogama/nixos-configuration
git add -A
git commit -m "docs: record alacritty reload behaviour and drop the stylix mention"
```

---

## Notes for the implementer

**The three traps, restated.** Each has already bitten this repo once:

1. Anything darkman rewrites must not be a `xdg.configFile`/`home.file` entry.
   A managed path is a read-only store symlink. This is why
   `services.darkman.settings` is pinned to `{ }`, why `gtk.theme` is not
   declared, and why `alacritty/colors.toml` and the `widgets` symlink are
   seeded by activation.
2. `lib.hm.dag.entryAfter` referencing a deleted entry breaks activation. Task 7
   deletes `quickshellLockDefault`, which `darkmanTimezoneSync` depends on.
3. `nix flake check` passing proves nothing about the generated QML. Only the
   live round trip does.

**Expect a cosmetic diff in hex case.** stylix emitted lowercase
(`#FFdf5273`); `theme-colors.nix` is uppercase (`#FF008DF8`). QML's colour
parser is case-insensitive, so this is noise — but every assertion in this plan
matches the uppercase form.

**The desktop is intentionally inconsistent between Tasks 1 and 3.** Task 1
changes mako, vicinae, the lockscreen and the greeter to the new palette while
the bar still renders Horizon from stylix. This is expected, not a bug; Task 3
closes it.
