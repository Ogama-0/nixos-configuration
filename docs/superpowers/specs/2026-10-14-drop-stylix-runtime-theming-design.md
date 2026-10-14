# Drop stylix, drive light/dark from darkman at runtime

Date: 2026-10-14
Status: approved design
Scope: `personal` profile only (`epita`, `epita-light`, `oserv` need no edits)

## Problem

stylix is a build-time theming system: it bakes one base16 palette and one
polarity into Nix store files. darkman is a runtime switcher. The two cannot
agree, and today stylix wins — `stylix.nix` pins `polarity = "dark"` and the
generated `gtk.iconTheme = "Papirus-Dark"`, so when darkman writes
`color-scheme = prefer-light` at sunrise the static files override the result.
That is why darkman currently appears to do almost nothing.

Goal: remove stylix entirely and make light/dark switching actually work at
runtime across the desktop — bar, all quickshell widgets, lockscreen,
zen-browser, alacritty, vicinae, GTK apps, notifications.

## What stylix actually contributes today

Measured by evaluating `homeConfigurations.personal`, not by reading
`autoEnable`:

- Program targets live: `helix`, `mpv`, `vim`, `zellij`, `zen-browser`.
- Opted out already: `alacritty`, `fish`, `mako`, `starship`, `swaylock`, `vicinae`.
- Non-program targets on: `gtk`, `sway`, `fontconfig`, `gnome`, `kde`,
  `xresources`, `nixos-icons`, `bat`, `fzf`, `yazi`, `zathura`.
- `gtk.theme = adw-gtk3`, `gtk.iconTheme = Papirus-Dark`.
- `config.lib.stylix.colors` and `config.stylix.polarity`, consumed directly by
  `display/sway/quickshell/default.nix` (bar + status widget) and
  `display/sway/mako.nix` (font only).
- Fonts, sizes, opacity, Papirus icons.

`stylix.homeModules.stylix` appears only in the `personal` homeConfiguration
(`flake.nix`). `oserv`, `epita`, `epita-light` never receive the module, and the
modules they share (`helix.nix`, `font.nix`, `gtk.nix`, `alacritty.nix`,
`zellij`, `sh.nix`, `git.nix`, `wakapi.nix`) reference no stylix option. Every
stylix reference in the tree is personal-only: `stylix.nix`, `firefox.nix`,
`sway/mako.nix`, `sway/quickshell/default.nix`, plus `flake.nix`.

## Surfaces that need no work

- **sway**: `sway/default.nix` sets `window.border = 0; titlebar = false`, so
  client border colours are never drawn. stylix's `#df5273` was dead weight.
  `fonts.names = [ "Noto Sans" ]` is already hand-set.
- **zen-browser**: `firefox.nix` already sets `zen.view.window.scheme = 2`
  (auto). stylix's generated userChrome was fighting it; removing stylix makes
  zen's switching better, not worse. Only the two `stylix.targets.*` blocks go.
- **vicinae**: already ships `horizon-dark` + `horizon-light` and selects by the
  XDG portal colour-scheme darkman drives. Untouched.
- **fontconfig**: `display/font.nix` already sets the same defaults and installs
  Inter, Merriweather, JetBrains Mono, Noto.
- **cursor**: owned by `home.pointerCursor` in `host/personal/home.nix`.
- **opacity**: only fed dropped targets; alacritty and vicinae set their own.
- **greeter**: `modules/nixosconf/greetd.nix` is already stylix-free and already
  makes its own sunrise/sunset decision through `pkgs/greetd-proxy` and
  `modules/lib/timezone-coords.nix`.
- **helix, vim, zellij, bat, yazi, zathura, mpv**: lose their generated themes
  and instead inherit the terminal's colours. Because alacritty becomes a
  switching surface (below), these follow light/dark for free. Note helix ships
  no built-in `horizon` theme — stylix was generating it — so helix falls back
  to its default theme. Accepted.

## Single source of truth

`modules/lib/theme-colors.nix` is already the declared place to change the
palette and already holds a `dark` and a `light` attrset. It becomes the only
palette source. `modules/lib/qml-theme.nix` already takes `colors` as a
parameter, which is what makes the two-tree approach below free.

## System dark palette: the terminal palette replaces Horizon dark

Decision: light mode stays **Horizon light**, unchanged. Dark mode system-wide
becomes the hand-picked palette currently living in `alacritty.nix` — pure black
ground, warm off-white text, vivid accents. `theme-colors.nix`'s `dark` attrset
is replaced wholesale; its `light` attrset is untouched. The file's header
comment (which currently says both palettes were transcribed from
`pkgs.base16-schemes`' horizon yaml files) must be corrected to describe the new
split provenance.

The source palette is ANSI-16; every consumer wants base16, which additionally
needs a greyscale ramp and an orange and spare slot that ANSI has no equivalent
for. Two values in `alacritty.nix`'s `let` block — `orange = "#f1895c"` and
`red = "#e95678"` — are currently defined but never referenced, and fill two of
those gaps.

| slot | value | provenance |
|---|---|---|
| `base00` | `000000` | terminal background |
| `base01` | `222222` | terminal normal black |
| `base02` | `444444` | terminal bright black |
| `base03` | `6A6A6A` | **derived**, continues the 00 -> 22 -> 44 ramp |
| `base04` | `B5B0AA` | **derived**, dim foreground, warm-tinted to match base05 |
| `base05` | `FFFAF3` | terminal foreground |
| `base06` | `FFFCF8` | **derived** |
| `base07` | `FFFFFF` | terminal white |
| `base08` | `FF273F` | terminal **bright** red |
| `base09` | `F1895C` | the unused `orange` from the `let` block |
| `base0A` | `FFB900` | terminal yellow |
| `base0B` | `27D796` | terminal green |
| `base0C` | `00D7EB` | terminal cyan |
| `base0D` | `008DF8` | terminal blue — the UI accent |
| `base0E` | `6C43A5` | terminal **bright** magenta |
| `base0F` | `E95678` | the unused `red` from the `let` block |

Three deliberate substitutions, chosen so the palette survives being used for UI
chrome rather than just text:

- `base08` takes the *bright* red `#FF273F` rather than normal `#FF000F`;
  near-pure red is punishing on borders and status bands.
- `base0E` takes the *bright* magenta `#6C43A5` rather than normal `#FF00FF`;
  pure fuchsia is unusable as a UI colour.
- Only `base03`, `base04` and `base06` are invented. Everything else is a colour
  already in use on this machine.

`base0D` is the UI accent — bar clock text, mako border, vicinae accent,
lockscreen highlights. It becomes blue `#008DF8`, where today it is Horizon's
pink-red `#DF5273`. This was chosen explicitly over keeping a pink accent, in
favour of fidelity to the terminal palette. Expect the bar, notifications and
launcher accent to read blue in dark mode.

Consumers affected by this palette swap, beyond the ones listed per-surface
below: the **greeter**. `modules/nixosconf/greetd.nix` renders through
`qml-theme.nix` with a variant out of `theme-colors.nix`, so the login screen
changes appearance too. That is intended, not collateral.

Note that alacritty's own dark `colors.toml` stays a **verbatim** copy of
today's settings rather than being regenerated from the new base16 slots. The
base16 mapping deliberately drops normal red `#FF000F` and normal magenta
`#FF00FF`, and the terminal should keep its full original ANSI set.

## Design, per surface

### 1. Deletion

- Delete `modules/home-manager/stylix.nix`.
- Remove its import from `host/personal/home.nix`.
- In `flake.nix`: remove `stylix.url`, `stylix.inputs.nixpkgs.follows`, the
  `stylix` function argument, and `stylix.homeModules.stylix` from the
  `personal` module list. The lockfile shrinks.

### 2. GTK — the core fix

Do **not** set `gtk.theme` or `gtk.iconTheme` through home-manager. The
home-manager gtk module writes both `gtk-3.0/settings.ini` and the dconf keys,
so every activation would stomp whatever mode darkman had selected. This is the
same trap already documented in `darkman.nix` for `settings = { }` and in
`gtk.nix` for `color-scheme`.

Instead:

- `display/gtk.nix` installs `pkgs.adw-gtk3` and `pkgs.papirus-icon-theme` via
  `home.packages` so the themes exist on disk, and keeps `dconf.enable = true`.
- `darkman.nix`'s existing `gtk-theme` script gains two more dconf writes beside
  the `color-scheme` write it already does:
  - `/org/gnome/desktop/interface/gtk-theme` → `adw-gtk3-dark` / `adw-gtk3`
  - `/org/gnome/desktop/interface/icon-theme` → `Papirus-Dark` / `Papirus-Light`

Store contents verified: `adw-gtk3` provides `adw-gtk3` and `adw-gtk3-dark`;
`papirus-icon-theme` provides `Papirus`, `Papirus-Dark`, `Papirus-Light`.

Risk: a GTK3 app that reads only `settings.ini` and ignores gsettings/the portal
would end up unthemed. libadwaita and GTK4 apps follow `color-scheme` natively.
If such an app turns up, revisit by writing `settings.ini` from the darkman
script too — not by handing the keys back to home-manager.

### 3. alacritty — the keystone

Making the terminal switch makes every TUI app switch with it.

- `programs.alacritty.settings` keeps its font and window settings, moves its
  colours out, and adds `general.import = [ "${config.xdg.configHome}/alacritty/colors.toml" ]`.
  `general.live_config_reload` defaults to true (alacritty 0.17.0).
- Two colour TOML files are generated. **The dark variant is today's
  hand-picked palette, preserved verbatim** — pure black `#000000` background,
  `#fffaf3` foreground, and the existing custom normal/bright sets — moved out
  of `programs.alacritty.settings.colors` unchanged, so dark mode looks exactly
  as it does now. stylix never themed alacritty
  (`targets.alacritty.enable = false`), so there is nothing to recover here.
  The light variant keeps Horizon light's background and foreground but uses
  **hand-tuned ANSI accents**, not the raw base16 slots. The naive base16 to
  ANSI mapping is unusable: Horizon light was never designed as a terminal
  palette, and it puts `base0A` ("yellow") at `#FBE0D9`, which measures
  **1.13:1** against the `#FDF0ED` background — invisible — while `base0D`
  ("blue") is a crimson `#DA103F` and `base0C` ("cyan") a red-orange `#DC3318`,
  so blue and cyan would both render red.

  Instead, the 8 accents are chosen as legible dark-on-light values, each
  measured against the `#FDF0ED` ground and clearing the 4.5:1 text floor. The
  rule for bright variants inverts the dark-mode convention: on a light ground
  "bright" means *darker*, i.e. more emphasis.

  | ANSI | normal | ratio | bright |
  |---|---|---|---|
  | background | `#FDF0ED` (`base00`) | — | — |
  | foreground | `#403C3D` (`base05`) | 9.8:1 | — |
  | black | `#201C1D` | 15.1:1 | `#6B6466` |
  | red | `#C5283D` | 5.0:1 | `#A61E30` |
  | green | `#2D7D46` | 4.6:1 | `#226336` |
  | yellow | `#846200` | 5.1:1 | `#6B4F00` |
  | blue | `#1E5FA8` | 5.8:1 | `#174B85` |
  | magenta | `#7B3FA0` | 6.2:1 | `#633280` |
  | cyan | `#15666C` | 6.0:1 | `#105055` |
  | white | `#403C3D` | 9.8:1 | `#201C1D` |

  Note on cyan: the status widget's light `upColor` is `#1D8991`, and that value
  stays correct there, because it is a filled band against a 3:1 floor. As
  *terminal text* `#1D8991` measures only 3.74:1, so the terminal uses the
  darker `#15666C`. Same hue, different floor — not an inconsistency.

  Accepted consequence: the two modes are not from one palette. Dark mode
  keeping its current look was chosen over cross-mode consistency.
- A darkman script **copies** the selected file's contents over
  `~/.config/alacritty/colors.toml`. It must copy, not symlink: alacritty's
  watcher keys on content change at that path, and re-pointing a symlink may not
  fire inotify.
- `colors.toml` must not be managed by `xdg.configFile` (read-only store
  symlink). Seed it on activation with `home.activation`, following the existing
  `darkmanTimezoneSync` pattern in `darkman.nix`.

Risk to verify empirically: whether alacritty live-reloads on a change to an
*imported* file rather than the main config. If it does not, the fallback is
that newly opened terminals pick up the new theme and existing ones do not —
acceptable, since alacritty exposes no reload signal. Decide this by test, not
by assumption.

### 4. quickshell — two generated trees

`qml-theme.nix` already takes `colors` as a parameter, so calling it twice
yields two complete themed trees with **zero QML edits**.

- Move the themed files from `quickshell/widgets/...` to
  `quickshell/widgets-dark/...` and `quickshell/widgets-light/...`, each
  generated by the same `themedQmlFile` helper with `colors.dark` / `colors.light`
  and the matching `laserColor` and status colours.
- `cava.conf` is duplicated into both trees. `Music.qml` resolves it as
  `Quickshell.shellDir + "/cava.conf"`, so `shellDir` makes this automatic.
- `~/.config/quickshell/widgets` becomes a plain symlink to one of the two
  trees, created by a `home.activation` entry named `quickshellThemeTree` (not
  `xdg.configFile`, for the same read-only reason). `quickshell -c widgets` resolves through it.
- darkman repoints that symlink and runs
  `systemctl --user restart quickshell-widgets` — the same restart
  `sway/default.nix` already performs.

This **removes** machinery rather than adding it. Each tree contains its own
correct `components/Lock.qml` directly, so the following all go away:

- the `Lock-dark.qml` / `Lock-light.qml` config entries (the `lockVariant`
  helper stays, but now emits `components/Lock.qml` inside each tree),
- the `quickshellLockDefault` activation entry,
- the two `quickshell-lock-theme` darkman scripts.

`darkman.nix`'s `home.activation.darkmanTimezoneSync` currently declares
`entryAfter [ "linkGeneration" "quickshellLockDefault" ]`. Since
`quickshellLockDefault` is being deleted, that list becomes
`entryAfter [ "linkGeneration" "quickshellThemeTree" ]`, or the activation will
fail on an unknown dependency.

The lock variants stay deliberately different designs, not one skin recoloured:
dark keeps the Arcane/Jinx artwork, light keeps the Nausicaa treatment. That
distinction lives in `LockDark.qml` / `LockLight.qml` and their images and is
preserved.

Alternative considered and rejected: a `Theme.qml` singleton holding both
palettes with a `mode` property bound via `FileView { watchChanges: true }`,
replacing all 26 `@token@` substitutions with runtime property bindings. It
switches with no restart flicker, but it means rewriting all 11 themed QML files
and reworking `greetd.nix`'s store-path call to `qml-theme.nix`. Not worth it to
avoid a brief flicker that occurs twice a day.

### 5. wallpapers split by mode

`assets/wallpaper/` becomes three directories:

- `dark/` — wallpapers only shown in dark mode
- `light/` — wallpapers only shown in light mode
- `both/` — wallpapers suitable for either mode

All four files currently in `assets/wallpaper/` move into `both/` via `git mv`:
`background_monocle.png`, `IMG-20260904-WA0008.jpg`,
`wallpaper_the_lords_of_the_rings.jpeg`,
`wp11126805-lord-of-the-rings-art-wallpapers.jpg`. `dark/` and `light/` start
empty.

Because git does not track empty directories, `dark/` and `light/` each need a
`.gitkeep`. Without it they would be absent from a fresh checkout and the
`find` below would emit a stderr warning on every start.

The pool is mode-specific: dark mode draws from `dark/` + `both/`, light mode
from `light/` + `both/`.

`Wallpaper.qml:67` currently hardcodes its search:

    find "$HOME/nixos-configuration/assets/wallpaper" -maxdepth 1 -type f ...

The directory list becomes a new `@wallpaperDirs@` substitution token, which
drops out of the two-tree design for free: the dark tree is generated with
`dark both`, the light tree with `light both`. `qml-theme.nix` gains the token
and a corresponding required argument, and the quickshell module passes the
per-variant value.

No persistence work is needed. `Wallpaper.qml` keeps no record of the current
selection — `listProc` picks a random image on startup and a `Timer` rotates
every 10 minutes. Since a theme switch restarts `quickshell-widgets`, the new
mode's pool takes effect immediately with a fresh random pick, and a wallpaper
from the outgoing mode's folder can never persist into the wrong mode.

Two existing references to the moved files must be updated in the same change:

- **`display/i3/default.nix:87`** uses
  `${../../../../assets/wallpaper/background_monocle.png}` as a **Nix path
  literal**, and `display/i3` is imported by **`epita`**. A Nix path literal
  must resolve at evaluation time, so leaving this stale breaks the `epita`
  profile's evaluation outright — not merely its wallpaper. Repoint it at
  `both/background_monocle.png`. This is the one place where the wallpaper
  reorganisation reaches outside the `personal` profile.
- **`stylix.nix:11,31`** also references `background_monocle.png`, but that file
  is being deleted wholesale, so nothing to repoint.

Unrelated cleanup, taken because it sits in the middle of this work:
`sway/default.nix:15-17` defines `wallpeper`, `wallpeper_blure`,
`wallpaper_tache` and `wallpeper_monocle` as `toString /background.png` and
friends — absolute paths to the filesystem root that do not exist. They are
never referenced; `toString` on a missing path does not error, so they have been
silently dead. Delete them.

`assets/wallpaper-bank/` (3 files) is a separate holding area that the picker
never reads. Left untouched.

### 6. mako

Already has dark colours, a `mode=light` block fed from `theme-colors.nix`, and
working darkman scripts. The only change: its two `config.stylix.fonts.*`
references become the literal `"Inter 14"` (the values stylix was supplying).

## Contrast

### Light mode: preserve, do not recompute

Already solved and must be inherited as-is. `quickshell/default.nix` carries
hand-measured light-mode values because Horizon puts teal at `base0C` in dark
but `base0E` in light, and several light slots fail contrast floors:

- `upColor` light `#FF1D8991` (the darker teal, clears 3:1 on the light ground)
- `degradedColor` light `#FFC2490B` (base09 `#F6661E` is only 2.4:1; darkened to 3.8:1)
- `downColor` light `#FFDA103F`
- `mutedColor` light `#CC${base05}` (base04 is 2.5:1 at 11px; this reaches 4.9:1)

The light tree takes these unchanged. The `polarity`-driven conditionals that
select them are replaced by per-tree constants.

### Dark mode: re-measured for the new palette

The old dark values were Horizon's and were measured against a composited ground
of `#1A1C23`. The new `base00` is pure black, so the status panel ground
(`@panelBg@` = `#E6` over the wallpaper) is darker, and the worst case — a fully
white wallpaper showing through 10% — is about `#1A1A1A`. Ratios against that
worst case, with the floors the existing comments establish (3:1 for filled
bands, 4.5:1 for the 11px latency column):

| token | new dark value | source | ratio | floor | verdict |
|---|---|---|---|---|---|
| `upColor` | `#FF00D7EB` | `base0C` cyan | 9.9:1 | 3:1 | pass |
| `degradedColor` | `#FFF1895C` | `base09` orange | 7.0:1 | 3:1 | pass |
| `downColor` | `#FFFF273F` | `base08` red | 4.7:1 | 3:1 | pass |
| `mutedColor` | `#FFB5B0AA` | `base04` | 8.1:1 | 4.5:1 | pass |

All four clear their floors with margin, because pure black is a more forgiving
ground than Horizon's `#1C1E26`. Unlike the light palette, dark mode therefore
needs no hand-tuned deviations from its base16 slots — the straight slot values
are sufficient. These ratios should be spot-checked during implementation rather
than trusted blindly.

## Verification

A green `nix flake check` does **not** prove the generated QML evaluates — the
substitution produces config text that Nix never parses. Verification therefore
requires, in order:

1. `nix flake check`.
2. Build all four configurations, to confirm removing the flake input broke no
   profile: `personal`, `oserv`, `epita`, `epita-light`.
3. A real `home-manager switch` for `personal` — only after explicitly asking.
4. A forced round trip: `darkman set light` then `darkman set dark`, checking
   each surface actually flips: GTK app chrome and icons, alacritty (existing
   window and a new one), the quickshell bar and widgets, the lockscreen, mako
   notifications, vicinae, zen.
5. Confirm the new dark palette landed where it should: the bar clock, mako
   border and vicinae accent should read blue `#008DF8` in dark mode, and the
   terminal's own ANSI set should be visibly unchanged from today.
6. Check the **greeter** separately — it renders from `theme-colors.nix` through
   `greetd.nix` and so changes with the palette, but it is a NixOS-side surface
   that a home-manager switch does not touch. Per `docs/greeter.md`, it can be
   previewed without rebooting.
7. Wallpapers: confirm the picker (`Mod+w`) lists only `both/` contents in both
   modes initially, then drop a test image into `dark/` and confirm it appears
   in dark mode and not in light. Confirm no `find: No such file or directory`
   on stderr in the service log.
8. Evaluate `epita` specifically after the wallpaper move, since its i3 module
   holds a Nix path literal into `assets/wallpaper/`.
9. `journalctl --user -u quickshell-widgets` clean across both switches.

## Out of scope

- Any change to `epita`, `epita-light`, or `oserv` beyond the flake input going away.
- The `Theme.qml` singleton refactor (rejected above).
- Changing the **light** palette: Horizon light stays exactly as it is. (The
  dark palette is replaced — see the system dark palette section.)
- The lock screens' artwork, and `assets/lockscreen/` generally: those images
  are already per-variant and are not folded into the new wallpaper layout.
- `assets/wallpaper-bank/`.
- Making sway client borders visible.
