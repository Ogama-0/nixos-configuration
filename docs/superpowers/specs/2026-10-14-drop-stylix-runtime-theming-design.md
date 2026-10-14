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

`modules/lib/theme-colors.nix` already holds both Horizon dark and light
palettes and is already the declared place to change the palette. It becomes the
only palette source. `modules/lib/qml-theme.nix` already takes `colors` as a
parameter, which is what makes the two-tree approach below free.

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
  The light variant is derived from `theme-colors.nix`'s `light` palette with
  the standard base16 to ANSI mapping:

  | ANSI | light source | ANSI | light source |
  |---|---|---|---|
  | background | `base00` | foreground | `base05` |
  | black | `base01` | bright black | `base03` |
  | red | `base08` | bright red | `base08` |
  | green | `base0B` | bright green | `base0B` |
  | yellow | `base0A` | bright yellow | `base0A` |
  | blue | `base0D` | bright blue | `base0D` |
  | magenta | `base0E` | bright magenta | `base0E` |
  | cyan | `base0C` | bright cyan | `base0C` |
  | white | `base05` | bright white | `base07` |

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

### 5. mako

Already has dark colours, a `mode=light` block fed from `theme-colors.nix`, and
working darkman scripts. The only change: its two `config.stylix.fonts.*`
references become the literal `"Inter 14"` (the values stylix was supplying).

## Light-palette contrast

Already solved and must be preserved, not recomputed. `quickshell/default.nix`
carries hand-measured light-mode values because Horizon puts teal at `base0C` in
dark but `base0E` in light, and several light slots fail contrast floors:

- `upColor` light `#FF1D8991` (the darker teal, clears 3:1 on the light ground)
- `degradedColor` light `#FFC2490B` (base09 `#F6661E` is only 2.4:1; darkened to 3.8:1)
- `downColor` light `#FFDA103F`
- `mutedColor` light `#CC${base05}` (base04 is 2.5:1 at 11px; this reaches 4.9:1)

The light tree inherits these as-is. The `polarity`-driven conditionals that
select them are replaced by per-tree constants.

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
5. `journalctl --user -u quickshell-widgets` clean across both switches.

## Out of scope

- Any change to `epita`, `epita-light`, or `oserv` beyond the flake input going away.
- The `Theme.qml` singleton refactor (rejected above).
- Changing the Horizon palette itself, or the lock screens' artwork.
- Making sway client borders visible.
