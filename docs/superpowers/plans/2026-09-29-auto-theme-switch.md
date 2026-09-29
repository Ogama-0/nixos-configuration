# Sunset/Sunrise Dark-Light Theme Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `personal` desktop switch live between the existing dark theme and a new light theme at local sunset/sunrise, without a rebuild.

**Architecture:** `services.darkman` (nixpkgs-packaged, has a home-manager module) computes sunset/sunrise from a lat/lng pair synced from `/etc/timezone`, and on each transition runs shell scripts that symlink-swap pre-baked dark/light variants of each target's themed assets into place and send that app a live-reload signal (or, where the app supports it natively, flips a runtime setting directly — gtk via dconf, mako via `makoctl mode`).

**Tech Stack:** Nix / home-manager, `services.darkman` (nixpkgs `darkman` package), stylix (kept only for the default one-time build-time theme; disabled per-target for anything this plan takes over), sway/waybar/mako/swaync/tofi/quickshell.

**Spec:** `docs/superpowers/specs/2026-09-29-auto-theme-switch-design.md`

## Global Constraints

- Scope is the `personal` profile only — `oserv`/`epita`/`epita-light` are untouched.
- Firefox/zen-browser stay statically themed via the existing `stylix.targets.firefox`/`zen-browser` build-time integration — out of scope, no scripts for it.
- `modules/home-manager/stylix.nix` keeps producing the dark theme (`horizon-dark.yaml`, `polarity = "dark"`) as the build-time default; darkman only adjusts runtime-mutable state after activation.
- Every target this plan takes over from stylix's `autoEnable` must have its `stylix.targets.<x>.enable = false` set explicitly in `modules/home-manager/stylix.nix`, so stylix and darkman never fight over the same file.
- Color values for both themes come from a single shared file (`modules/home-manager/lib/theme-colors.nix`) — no hex literal is repeated by hand in more than one place.

**Deviation from spec to flag for review:** the spec's design called for parsing `horizon-dark.yaml`/`horizon-light.yaml` from `pkgs.base16-schemes` at eval time so the scheme files stay the single source of truth. Nix has no built-in YAML parser, and reaching a parsed value would require import-from-derivation (running `yq`/`remarshal` in a builder) for two small, static files. Task 1 instead hand-transcribes both palettes once into `modules/home-manager/lib/theme-colors.nix`, with a comment citing the exact upstream file each block mirrors, and every other file imports from there — so there is still exactly one place to edit, it's just a Nix file instead of a parsed YAML file. Flag this in plan review; if parsing from the YAML directly is a hard requirement, Task 1 needs to change before implementation starts.

## Review Focus

- Timezone not in the lookup table (e.g. a genuinely new travel destination) — the sync script must fall back to Paris coordinates rather than crash or leave darkman unconfigured (Task 2).
- A `home-manager switch` running while darkman is mid-transition (or vice versa) — switch always resets the active symlinks back to the dark default, so after any rebuild the user could silently be back on dark until the next sunset/sunrise event; this is accepted default behavior but must be visible in a task's verification step, not just assumed (Task 1's gtk verification step, and each later task touching a live target re-verifies post-switch state). Final scope note: waybar/swaync were dropped from darkman entirely (their modules are dormant/unwired on `personal`, see Task 4/6 commit history), and the quickshell bar/widget shell was excluded from theming (only its lockscreen switches) — so in practice this concern applies to gtk, mako, tofi, and the quickshell lockscreen only.
- Two theming systems fighting over the same generated file (stylix's `autoEnable` vs. this plan's hand-baked variants) — every task that takes over a target must confirm the corresponding `stylix.targets.<x>.enable = false` is set and `nix flake check` still passes (Tasks 3-7).
- `darkman set dark`/`darkman set light` run back-to-back (rapid toggling) — symlink swaps must be atomic (`ln -sf`) so a partially-written config is never read mid-swap (all of Tasks 3-7 use `ln -sf`, verified in each task's manual check).
- Missing `/etc/timezone` file (e.g. first boot before it's ever written) — sync script must not throw and must fall back to the default Paris coordinates (Task 2).

---

## File Structure

- **Create** `modules/home-manager/lib/theme-colors.nix` — the two base16 palettes (dark/light), a plain attrset, imported everywhere colors are needed.
- **Create** `modules/home-manager/darkman.nix` — `services.darkman` config: lat/lng defaults, the timezone-sync activation script, and the growing `darkModeScripts`/`lightModeScripts` attrsets (one key added per later task).
- **Modify** `modules/home-manager/display/gtk.nix` — no file changes needed (dconf key already reads `stylix.polarity`; darkman just writes the same key directly at runtime — logic lives in `darkman.nix`).
- **Modify** `modules/home-manager/stylix.nix` — disable `targets.mako`/`waybar`/`tofi`/`swaync` as each task takes them over.
- **Modify** `modules/home-manager/display/sway/mako.nix` — add real dark colors + a `mode=light` override block.
- **Modify** `modules/home-manager/display/hyprland/waybar.nix` — replace the commented-out static style with a real one that imports a runtime-swappable `colors.css`; add two color files.
- **Modify** `modules/home-manager/display/tofi.nix` — replace `programs.tofi` with two hand-written full config variants + a runtime symlink.
- **Modify** `modules/home-manager/display/hyprland/swaync.nix` — replace the commented-out static style with a real one that imports a runtime-swappable `colors.css`; add two color files.
- **Modify** `modules/home-manager/display/sway/quickshell/default.nix` — dual-bake only the lockscreen component (`Lock-dark.qml`/`Lock-light.qml`); the bar/widget shell is under active development and stays untouched, no service restart.
- **Modify** `host/personal/home.nix` — import `../../modules/home-manager/darkman.nix`.

---

### Task 1: Shared palette + darkman skeleton + gtk wiring

**Files:**
- Create: `modules/home-manager/lib/theme-colors.nix`
- Create: `modules/home-manager/darkman.nix`
- Modify: `host/personal/home.nix`

**Interfaces:**
- Produces: `import ../lib/theme-colors.nix` returns `{ dark = { base00 = "1C1E26"; ... base0F = "E4A382"; }; light = { base00 = "FDF0ED"; ... base0F = "E58C92"; }; }` (hex digits only, no `#` prefix, matching stylix's `config.lib.stylix.colors` convention so later tasks can `"#${colors.dark.base00}"` consistently).
- Produces: `services.darkman.darkModeScripts` / `lightModeScripts` attrsets in `darkman.nix`, extended by every later task.

- [ ] **Step 1: Write the palette file**

```nix
# modules/home-manager/lib/theme-colors.nix
#
# Hand-transcribed from pkgs.base16-schemes' horizon-dark.yaml and
# horizon-light.yaml (Nix has no YAML parser; see plan deviation note).
# Update this file, not any hex literal elsewhere, if the palette changes.
{
  dark = {
    base00 = "1C1E26";
    base01 = "232530";
    base02 = "2E303E";
    base03 = "6F6F70";
    base04 = "9DA0A2";
    base05 = "CBCED0";
    base06 = "DCDFE4";
    base07 = "E3E6EE";
    base08 = "E93C58";
    base09 = "E58D7D";
    base0A = "EFB993";
    base0B = "EFAF8E";
    base0C = "24A8B4";
    base0D = "DF5273";
    base0E = "B072D1";
    base0F = "E4A382";
  };
  light = {
    base00 = "FDF0ED";
    base01 = "FADAD1";
    base02 = "F9CBBE";
    base03 = "BDB3B1";
    base04 = "948C8A";
    base05 = "403C3D";
    base06 = "302C2D";
    base07 = "201C1D";
    base08 = "F7939B";
    base09 = "F6661E";
    base0A = "FBE0D9";
    base0B = "94E1B0";
    base0C = "DC3318";
    base0D = "DA103F";
    base0E = "1D8991";
    base0F = "E58C92";
  };
}
```

- [ ] **Step 2: Verify it evaluates**

Run: `nix eval --file modules/home-manager/lib/theme-colors.nix --json`
Expected: prints the JSON attrset with both `dark` and `light` keys, no errors.

- [ ] **Step 3: Write the darkman module skeleton**

```nix
# modules/home-manager/darkman.nix
{ pkgs, lib, config, ... }:
let
  dconfExe = "${pkgs.dconf}/bin/dconf";
in
{
  services.darkman = {
    enable = true;
    package = pkgs.darkman;

    settings = {
      # Defaults to Paris; Task 2 overrides this from /etc/timezone at
      # every home-manager activation.
      lat = 48.8566;
      lng = 2.3522;
      usegeoclue = false;
    };

    darkModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
      '';
    };

    lightModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
      '';
    };
  };
}
```

- [ ] **Step 4: Import the module**

Edit `host/personal/home.nix`, add to the `imports` list (after the existing `../../modules/home-manager/stylix.nix` line):

```nix
    ../../modules/home-manager/darkman.nix
```

- [ ] **Step 5: Verify the flake evaluates**

Run: `nix flake check`
Expected: no errors.

- [ ] **Step 6: Switch and manually verify gtk toggling**

Run: `home-manager switch --flake .#personal`
Then: `darkman set dark && dconf read /org/gnome/desktop/interface/color-scheme` — expect `'prefer-dark'`.
Then: `darkman set light && dconf read /org/gnome/desktop/interface/color-scheme` — expect `'prefer-light'`.
Then: `systemctl --user status darkman` — expect `active (running)`.

- [ ] **Step 7: Commit**

```bash
git add modules/home-manager/lib/theme-colors.nix modules/home-manager/darkman.nix host/personal/home.nix
git commit -m "feat: add darkman service with gtk dark/light switching"
```

---

### Task 2: Sync lat/lng from `/etc/timezone`

**Files:**
- Modify: `modules/home-manager/darkman.nix`

**Interfaces:**
- Consumes: `config.xdg.configHome` (home-manager standard option, already available in every home-manager module).
- Produces: `home.activation.darkmanTimezoneSync`, a home-manager activation script that runs on every `home-manager switch`.

- [ ] **Step 1: Add the lookup table and sync script**

```nix
# modules/home-manager/darkman.nix — add inside the `let` block:
  bashExe = "${pkgs.bash}/bin/bash";
  coreutils = pkgs.coreutils;

  # Mirrors host/personal/configuration.nix's time.timeZone and its two
  # commented-out travel alternates.
  timezoneCoords = {
    "Europe/Paris" = { lat = "48.8566"; lng = "2.3522"; };
    "America/Monterrey" = { lat = "25.6866"; lng = "-100.3161"; };
    "America/Mazatlan" = { lat = "23.2494"; lng = "-106.4111"; };
  };

  # Paris is the fallback for an unrecognized/missing timezone.
  fallbackLat = "48.8566";
  fallbackLng = "2.3522";

  timezoneCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (tz: c: ''
      if [ "$TZ_VALUE" = "${tz}" ]; then LAT="${c.lat}"; LNG="${c.lng}"; fi
    '') timezoneCoords
  );

  syncScript = pkgs.writeShellScript "darkman-timezone-sync" ''
    set -eu
    TZ_VALUE=""
    if [ -r /etc/timezone ]; then
      TZ_VALUE=$(${coreutils}/bin/cat /etc/timezone)
    fi
    LAT="${fallbackLat}"
    LNG="${fallbackLng}"
    ${timezoneCases}
    ${coreutils}/bin/mkdir -p "${config.xdg.configHome}/darkman"
    ${coreutils}/bin/cat > "${config.xdg.configHome}/darkman/config.yaml" <<EOF
    lat: $LAT
    lng: $LNG
    usegeoclue: false
    EOF
  '';
```

- [ ] **Step 2: Wire it as a home-manager activation script**

```nix
# modules/home-manager/darkman.nix — add to the top-level attrset, alongside `services.darkman`:
  home.activation.darkmanTimezoneSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${bashExe} ${syncScript}
  '';
```

Note: this activation script writes `${config.xdg.configHome}/darkman/config.yaml` directly, so the static `settings = { lat = ...; lng = ...; }` block from Task 1 stops being the effective config file after the first activation — leave it in place as the value used before the very first `home-manager switch` (e.g. during `nix flake check`'s evaluation) and as a readable default; it is intentionally overwritten at runtime. Adjust the `services.darkman.settings` comment to say so.

- [ ] **Step 3: Verify it evaluates**

Run: `nix flake check`
Expected: no errors.

- [ ] **Step 4: Switch and verify the synced file**

Run: `home-manager switch --flake .#personal`
Then: `cat /etc/timezone` — note the value (expect `Europe/Paris` on this host).
Then: `cat ~/.config/darkman/config.yaml` — expect `lat: 48.8566` / `lng: 2.3522`.

- [ ] **Step 5: Verify the fallback path directly**

Run the sync script with a fake unrecognized timezone to confirm it falls back instead of erroring:
```bash
TZ_VALUE_TEST=$(nix eval --file modules/home-manager/darkman.nix --json 2>/dev/null || true)
echo 'Pacific/Fakezone' | sudo tee /tmp/fake-timezone >/dev/null
bash -c '
  TZ_VALUE=$(cat /tmp/fake-timezone)
  LAT="48.8566"; LNG="2.3522"
  if [ "$TZ_VALUE" = "Europe/Paris" ]; then LAT="48.8566"; LNG="2.3522"; fi
  if [ "$TZ_VALUE" = "America/Monterrey" ]; then LAT="25.6866"; LNG="-100.3161"; fi
  if [ "$TZ_VALUE" = "America/Mazatlan" ]; then LAT="23.2494"; LNG="-106.4111"; fi
  echo "LAT=$LAT LNG=$LNG"
'
```
Expected: `LAT=48.8566 LNG=2.3522` (the fallback, since `Pacific/Fakezone` matches none of the `if` branches).

- [ ] **Step 6: Commit**

```bash
git add modules/home-manager/darkman.nix
git commit -m "feat: sync darkman coordinates from /etc/timezone on activation"
```

---

### Task 3: mako dark/light

**Files:**
- Modify: `modules/home-manager/display/sway/mako.nix`
- Modify: `modules/home-manager/stylix.nix`
- Modify: `modules/home-manager/darkman.nix`

**Interfaces:**
- Consumes: `import ../../lib/theme-colors.nix` (`dark`/`light` attrsets from Task 1).

- [ ] **Step 1: Disable stylix's mako target**

Edit `modules/home-manager/stylix.nix`, add alongside the other disabled targets:

```nix
    targets.mako.enable = false;
```

- [ ] **Step 2: Fill in real dark colors and a light mode block**

Edit `modules/home-manager/display/sway/mako.nix`:

```nix
{ pkgs, ... }:
let
  colors = import ../../lib/theme-colors.nix;
in
{
  services.mako = {
    enable = true;
    settings = {

      max-visible = 3;
      default-timeout = 7000;

      background-color = "#${colors.dark.base00}";
      text-color = "#${colors.dark.base05}";
      border-color = "#${colors.dark.base0D}";

      border-radius = 15;
      border-size = 0;

      sort = "-priority";
      height = 350;
      max-icon-size = 55;
      padding = "10";

      "mode=dnd" = { invisible = 1; };

      "mode=light" = {
        background-color = "#${colors.light.base00}";
        text-color = "#${colors.light.base05}";
        border-color = "#${colors.light.base0D}";
      };

      "mode=normal" = { };
      "mode=critical" = {
        background-color = "#${colors.dark.base08}";
        text-color = "#${colors.dark.base00}";
      };
      "mode=low" = { };
    };

    # rules = [
    #   {
```

(leave the remaining commented-out `rules` block below untouched.)

- [ ] **Step 3: Add darkman scripts**

Edit `modules/home-manager/darkman.nix`, extend the existing attrsets:

```nix
    darkModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
      '';
      mako = ''
        ${pkgs.mako}/bin/makoctl mode -r light
      '';
    };

    lightModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
      '';
      mako = ''
        ${pkgs.mako}/bin/makoctl mode -a light
      '';
    };
```

- [ ] **Step 4: Verify**

Run: `nix flake check`
Expected: no errors.

Run: `home-manager switch --flake .#personal`
Then: `darkman set dark && notify-send "test dark"` — expect a notification with the dark palette's background.
Then: `darkman set light && notify-send "test light"` — expect a notification with the light palette's background.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/display/sway/mako.nix modules/home-manager/stylix.nix modules/home-manager/darkman.nix
git commit -m "feat: switch mako notification colors with darkman"
```

---

### Task 4: waybar dark/light

**Files:**
- Modify: `modules/home-manager/display/hyprland/waybar.nix`
- Modify: `modules/home-manager/stylix.nix`
- Modify: `modules/home-manager/darkman.nix`

**Interfaces:**
- Consumes: `import ../../lib/theme-colors.nix`.

- [ ] **Step 1: Disable stylix's waybar target**

Edit `modules/home-manager/stylix.nix`, replace:
```nix
    targets.waybar = {
      enable = true;
      opacity.enable = false;
    };
```
with:
```nix
    targets.waybar.enable = false;
```

- [ ] **Step 2: Generate the two color files and a real style**

Edit `modules/home-manager/display/hyprland/waybar.nix` — replace the file's `let`-less top with a `let` block, replace the fully-commented `style` with a real one importing `colors.css`, and keep `xdg.configFile` entries for both variants:

```nix
{ pkgs, config, ... }:
let
  colors = import ../../lib/theme-colors.nix;

  colorDefs = c: ''
    @define-color base00 #${c.base00};
    @define-color base03 #${c.base03};
    @define-color base05 #${c.base05};
    @define-color base07 #${c.base07};
    @define-color base08 #${c.base08};
    @define-color base09 #${c.base09};
    @define-color base0B #${c.base0B};
    @define-color base0C #${c.base0C};
    @define-color base0D #${c.base0D};
    @define-color base0E #${c.base0E};
  '';
in
{
  xdg.configFile = {
    "waybar/colors-dark.css".text = colorDefs colors.dark;
    "waybar/colors-light.css".text = colorDefs colors.light;
  };

  home.activation.waybarColorDefault = pkgs.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/waybar/colors-dark.css" "${config.xdg.configHome}/waybar/colors.css"
  '';

  programs.waybar = {
    enable = true;

    settings = {
      mainBar = {
        height = 30;
        position = "bottom";
        spacing = 5;

        modules-left = [ "hyprland/workspaces" "custom/media" ];

        modules-center = [ "hyprland/window" ];
        modules-right = [
          "mpd"
          "pulseaudio"
          "network"
          "power-profiles-daemon"
          "backlight"
          "battery"
          "battery#bat2"
          "clock"
          "tray"
        ];

        keyboard-state = {
          numlock = true;
          capslock = true;
          format = "{name} {icon}";
          format-icons = {
            locked = "";
            unlocked = "";
          };
        };

        "sway/mode" = { format = ''<span style="italic">{}</span>''; };

        "sway/scratchpad" = {
          format = "{icon} {count}";
          show-empty = false;
          format-icons = [ "" "" ];
          tooltip = true;
          tooltip-format = "{app}: {title}";
        };

        mpd = {
          format =
            "{stateIcon} {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}{artist} - {album} - {title} ({elapsedTime:%M:%S}/{totalTime:%M:%S}) ⸨{songPosition}|{queueLength}⸩ {volume}% ";
          format-disconnected = "Disconnected ";
          format-stopped =
            "{consumeIcon}{randomIcon}{repeatIcon}{singleIcon}Stopped ";
          unknown-tag = "N/A";
          interval = 5;

          consume-icons.on = " ";
          random-icons = {
            off = ''<span color="#e93c58"></span> '';
            on = " ";
          };
          repeat-icons.on = " ";
          single-icons.on = " ";
          state-icons = {
            paused = "";
            playing = "";
          };
        };

        tray = { spacing = 10; };

        clock = {
          tooltip-format = ''
            <big>{:%Y %B}</big>
            <tt><small>{calendar}</small></tt>'';
          format-alt = "{:%Y-%m-%d}";
        };

        backlight = {
          format = "{percent}% {icon}";
          format-icons = [ "" "" "" "" "" "" "" "" "" ];
          on-click = "swaync-client -t";
        };

        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{capacity}% {icon}";
          format-full = "{capacity}% {icon}";
          format-charging = "{capacity}% ";
          format-plugged = "{capacity}% ";
          format-alt = "{time} {icon}";
          format-icons = [ "" "" "" "" "" ];
        };

        "battery#bat2" = { bat = "BAT2"; };

        power-profiles-daemon = {
          format = "{icon}";
          tooltip = true;
          tooltip-format = ''
            Power profile: {profile}
            Driver: {driver}'';
          format-icons = {
            default = "";
            performance = "";
            balanced = "";
            power-saver = "";
          };
        };

        network = {
          format-wifi = "{essid} ({signalStrength}%) ";
          format-ethernet = "{ipaddr}/{cidr} ";
          tooltip-format = "{ifname} via {gwaddr} ";
          format-linked = "{ifname} (No IP) ";
          format-disconnected = "Disconnected ⚠";
          format-alt = "{ifname}: {ipaddr}/{cidr}";
        };

        pulseaudio = {
          format = "{volume} % {icon} {format_source}";
          format-bluetooth = "{volume} % {icon}  {format_source}";
          format-bluetooth-muted = "🔇 {icon} {format_source}";
          format-muted = "🔇 {format_source}";
          format-source = "{volume}% ";
          format-source-muted = "";
          format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = [ "" "" "" ];
          };
          on-click = "pavucontrol";
        };
      };
    };

    style = ''
      @import url("colors.css");

      window#waybar {
        background-color: @base00;
        color: @base05;
      }

      #clock,
      #battery,
      #network,
      #pulseaudio,
      #tray,
      #power-profiles-daemon,
      #backlight,
      #mpd {
        padding: 0 10px;
        color: @base05;
      }

      #workspaces button {
        padding: 0 5px;
        background-color: transparent;
        color: @base05;
      }

      #workspaces button.focused,
      #workspaces button.active {
        background-color: @base02;
        box-shadow: inset 0 -3px @base0D;
      }

      #battery.charging,
      #battery.plugged {
        color: @base00;
        background-color: @base0B;
      }

      #battery.critical:not(.charging) {
        background-color: @base08;
        color: @base00;
      }

      #network.disconnected {
        background-color: @base08;
      }
    '';
  };

  wayland.windowManager.hyprland.settings.exec-once = [ "waybar" ];
}
```

(this trims the long list of commented-out rules from the original file down to a working real stylesheet using the same class names that mattered — `window#waybar`, common modules, workspace focus/active, battery charging/critical, network disconnected — since the rest were dead CSS for modules not even enabled in `modules-right`.)

- [ ] **Step 3: Add darkman scripts**

Edit `modules/home-manager/darkman.nix`:

```nix
    darkModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
      '';
      mako = ''
        ${pkgs.mako}/bin/makoctl mode -r light
      '';
      waybar-theme = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/waybar/colors-dark.css" "${config.xdg.configHome}/waybar/colors.css"
        ${pkgs.procps}/bin/pkill -x -SIGUSR2 waybar || true
      '';
    };

    lightModeScripts = {
      gtk-theme = ''
        ${dconfExe} write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
      '';
      mako = ''
        ${pkgs.mako}/bin/makoctl mode -a light
      '';
      waybar-theme = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/waybar/colors-light.css" "${config.xdg.configHome}/waybar/colors.css"
        ${pkgs.procps}/bin/pkill -x -SIGUSR2 waybar || true
      '';
    };
```

(`|| true` since waybar may not be running when darkman fires, e.g. during a headless test switch.)

- [ ] **Step 4: Verify**

Run: `nix flake check`
Expected: no errors.

Run: `home-manager switch --flake .#personal`, restart sway (or `swaymsg reload` + relaunch waybar), then:
`darkman set dark` — expect waybar background matches `#${colors.dark.base00}` (`#1C1E26`).
`darkman set light` — expect waybar background matches `#${colors.light.base00}` (`#FDF0ED`), no waybar restart needed (SIGUSR2 live-reloads CSS).

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/display/hyprland/waybar.nix modules/home-manager/stylix.nix modules/home-manager/darkman.nix
git commit -m "feat: switch waybar colors with darkman"
```

---

### Task 5: tofi dark/light

**Files:**
- Modify: `modules/home-manager/display/tofi.nix`
- Modify: `modules/home-manager/stylix.nix`
- Modify: `modules/home-manager/darkman.nix`

**Interfaces:**
- Consumes: `import ../lib/theme-colors.nix`.

- [ ] **Step 1: Disable stylix's tofi target**

Edit `modules/home-manager/stylix.nix`, remove `targets.tofi.enable = true;` and replace with:
```nix
    targets.tofi.enable = false;
```

- [ ] **Step 2: Replace `programs.tofi` with two hand-written variants**

Edit `modules/home-manager/display/tofi.nix`:

```nix
{ lib, pkgs, config, ... }:
let
  colors = import ../lib/theme-colors.nix;

  tofiConfig = c: ''
    horizontal = true
    anchor = top
    width = 100%
    height = 45

    padding-left = 20
    padding-top = 11

    outline-width = 0
    border-width = 0

    min-input-width = 100
    result-spacing = 20

    text-color = #${c.base05}
    background-color = #${c.base00}

    prompt-text =  
    prompt-padding = 30
    prompt-background = #${c.base02}
    prompt-background-corner-radius = 5
    prompt-background-padding = 4, 8

    input-color = #${c.base05}
    input-background = #${c.base02}
    input-background-corner-radius = 5
    input-background-padding = 4, 10

    selection-color = #${c.base0D}
    selection-background = #${c.base02}
    selection-match-color = #${c.base0B}
    selection-background-corner-radius = 5
    selection-background-padding = 4, 10

    clip-to-padding = false
    history = true
  '';
in
{
  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    "Mod4+d" = "exec tofi-drun | xargs swaymsg exec --";
    "Mod4+shift+d" = "exec tofi-run | xargs swaymsg exec --";
  };

  home.packages = [ pkgs.tofi ];

  xdg.configFile = {
    "tofi/config-dark".text = tofiConfig colors.dark;
    "tofi/config-light".text = tofiConfig colors.light;
  };

  home.activation.tofiConfigDefault = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/tofi/config-dark" "${config.xdg.configHome}/tofi/config"
  '';
}
```

- [ ] **Step 3: Add darkman scripts**

Edit `modules/home-manager/darkman.nix`:

```nix
      tofi = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/tofi/config-dark" "${config.xdg.configHome}/tofi/config"
      '';
```
(add to `darkModeScripts`; light variant, `config-light`, added to `lightModeScripts`.)

- [ ] **Step 4: Verify**

Run: `nix flake check`
Expected: no errors.

Run: `home-manager switch --flake .#personal`
Then: `darkman set dark && cat ~/.config/tofi/config | grep background-color` — expect `#${colors.dark.base00}`.
Then: `darkman set light && cat ~/.config/tofi/config | grep background-color` — expect `#${colors.light.base00}`.
Then launch `tofi-drun` manually and visually confirm the palette (tofi reads its config fresh each launch, no reload signal needed).

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/display/tofi.nix modules/home-manager/stylix.nix modules/home-manager/darkman.nix
git commit -m "feat: switch tofi colors with darkman"
```

---

### Task 6: swaync dark/light

**Files:**
- Modify: `modules/home-manager/display/hyprland/swaync.nix`
- Modify: `modules/home-manager/stylix.nix`
- Modify: `modules/home-manager/darkman.nix`

**Interfaces:**
- Consumes: `import ../../lib/theme-colors.nix`.

- [ ] **Step 1: Disable stylix's swaync target (if enabled by autoEnable)**

Edit `modules/home-manager/stylix.nix`, add:
```nix
    targets.swaync.enable = false;
```

- [ ] **Step 2: Generate the two color files and a real style**

Edit `modules/home-manager/display/hyprland/swaync.nix`, add near the top (after the existing `let`) and replace the commented `style` with a real one:

```nix
{ pkgs, config, lib, ... }:
let
  script_path = ../../../../scripts/swaync;
  colors = import ../../lib/theme-colors.nix;

  colorDefs = c: ''
    @define-color base00 #${c.base00};
    @define-color base02 #${c.base02};
    @define-color base05 #${c.base05};
    @define-color base08 #${c.base08};
    @define-color base0D #${c.base0D};
  '';

  wifi = {
    command = script_path + "/wifi-toggle.sh";
    update-command = script_path + "/update-wifi-toggle.sh";
  };
  bluetooth = {
    command = script_path + "/bluetooth-toggle.sh";
    update-command = script_path + "/update-bluetooth-toggle.sh";
  };
  power = {
    command = script_path + "/power-toggle.sh";
    update-command = script_path + "/update-power-toggle.sh";
  };
  night-shift = {
    command = script_path + "/night-shift-toggle.sh";
    update-command = script_path + "/update-night-shift-toggle.sh";
  };
in {

  xdg.configFile = {
    "swaync/colors-dark.css".text = colorDefs colors.dark;
    "swaync/colors-light.css".text = colorDefs colors.light;
  };

  home.activation.swayncColorDefault = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/swaync/colors-dark.css" "${config.xdg.configHome}/swaync/colors.css"
  '';

  services.swaync = {
    enable = true;
    settings = {

      positionX = "right";
      positionY = "bottom";

      control-center-positionX = "none";
      control-center-positionY = "none";
      control-center-margin-top = 8;
      control-center-margin-bottom = 8;
      control-center-margin-right = 8;
      control-center-margin-left = 8;
      control-center-width = 500;
      control-center-height = 700;

      fit-to-screen = false;
      layer-shell-cover-screen = true;

      layer-shell = true;
      layer = "overlay";
      control-center-layer = "overlay";
      cssPriority = "user";

      notification-body-image-height = 100;
      notification-body-image-width = 200;
      notification-inline-replies = false;

      timeout = 5;
      timeout-low = 3;
      timeout-critical = 0;
      notification-window-width = 500;
      keyboard-shortcuts = true;
      image-visibility = "always";
      transition-time = 200;
      hide-on-clear = true;
      hide-on-action = true;
      script-fail-notify = true;

      widgets = [ "inhibitors" "dnd" "mpris" "buttons-grid" "notifications" ];

      widget-config = {
        buttons-grid = {
          buttons-per-row = 4;
          actions = [
            ({
              label = "󰤨";
              type = "toggle";
              active = true;
            } // wifi)

            ({
              label = "󰂯";
              active = true;
              type = "toggle";
            } // bluetooth)

            ({
              label = "󰾅";
              type = "button";
            } // power)
            ({
              label = "🔅";
              active = true;
              type = "button";
            } // night-shift)

          ];

        };
      };
    };
    style = ''
      @import url("colors.css");

      :root {
        --border-radius: 22px;
        --cc-bg: @base00;
        --widget-background: @base02;
        --padding: calc(var(--border-radius) / 2);
      }

      .notification-group {
        background: @base00;
        color: @base05;
        border-radius: var(--border-radius);
        padding: 8px;
      }

      .notification-background.critical {
        background: @base08;
      }

      .widgets > .widget {
        background: var(--widget-background);
        color: @base05;
        padding: calc(var(--border-radius) / 2);
      }
    '';
  };
}
```

- [ ] **Step 3: Add darkman scripts**

Edit `modules/home-manager/darkman.nix`:

```nix
      swaync = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/swaync/colors-dark.css" "${config.xdg.configHome}/swaync/colors.css"
        ${pkgs.swaynotificationcenter}/bin/swaync-client --reload-css || true
      '';
```
(add to `darkModeScripts`; light variant with `colors-light.css`, added to `lightModeScripts`.)

- [ ] **Step 4: Verify**

Run: `nix flake check`
Expected: no errors.

Run: `home-manager switch --flake .#personal`
Then: `darkman set dark && swaync-client -t` — open the panel, expect dark background.
Then: `darkman set light && swaync-client -t` — expect light background, no swaync restart needed.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/display/hyprland/swaync.nix modules/home-manager/stylix.nix modules/home-manager/darkman.nix
git commit -m "feat: switch swaync colors with darkman"
```

---

### Task 7: quickshell lockscreen dark/light (bar excluded)

**Scope note (superseded the original plan text below the line, per user instruction mid-execution):** the quickshell bar/widget shell (`shell.qml`, `Wallpaper.qml`, `Clock.qml`, `Music.qml`, `Calendar.qml`, `RevealMask.qml`, `LaserBar.qml`) is still under active development by the user and must **not** be touched, dual-baked, restructured, or have its systemd service restarted by this task. Only the lockscreen (`components/Lock.qml`, already split into a stable `LockDark.qml`/`LockLight.qml` pair) is in scope. The existing bar/widget-shell generation in `modules/home-manager/display/sway/quickshell/default.nix` (the `themedQmlFile`/`perVariantFiles`-style logic, or whatever form it currently takes) stays exactly as-is — read the file's current state before editing and change nothing outside what's described below.

**Files:**
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`
- Modify: `modules/home-manager/darkman.nix`

**Interfaces:**
- Consumes: `import ../../../lib/theme-colors.nix`.
- Note: this task does **not** touch `stylix.nix`.

- [ ] **Step 1: Dual-bake only the lockscreen component**

Edit `modules/home-manager/display/sway/quickshell/default.nix`. Leave every existing binding and `xdg.configFile` entry that builds the bar/widget shell untouched. Add a new lockscreen-only token-substitution helper and two new `xdg.configFile` entries (`components/Lock-dark.qml`, `components/Lock-light.qml`), replacing whatever single `components/Lock.qml` entry currently exists (which today picks `LockDark.qml`/`LockLight.qml` at build time via `stylix.polarity`) with these two variants plus a runtime-swappable default:

```nix
  # Lockscreen-only theming — reuses the same @token@ substitution the file
  # already uses for the bar, but keyed off the shared palette instead of
  # config.lib.stylix.colors, and scoped to just the lock component. Do not
  # extend this to shell.qml/Wallpaper/Clock/Music/Calendar/RevealMask/
  # LaserBar — those are the in-progress bar and are out of scope.
  lockThemeColors = import ../../../lib/theme-colors.nix;

  withLockThemeColors = c: laserColor: builtins.replaceStrings
    [
      "@cardBg@"
      "@cardBorder@"
      "@clockColor@"
      "@dateColor@"
      "@dividerColor@"
      "@tempColor@"
      "@lockBg@"
      "@systemctlBin@"
      "@lockscreenImage@"
      "@laserColor@"
      "@greenColor@"
      "@redColor@"
    ]
    [
      "#B3${c.base00}"
      "#33${c.base05}"
      "#FF${c.base05}"
      "#CC${c.base04}"
      "#22${c.base03}"
      "#FF${c.base0D}"
      "#FF${c.base00}"
      "${pkgs.systemd}/bin/systemctl"
      "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png"
      laserColor
      "#FF${c.base0B}"
      "#FF${c.base08}"
    ];

  lockVariant = variant: lockComponent: {
    text = withLockThemeColors lockThemeColors.${variant}
      (if variant == "light" then "#FFFFFF" else "#000000")
      (builtins.readFile lockComponent);
  };
```

Add to the existing `xdg.configFile` attrset (alongside whatever bar-related entries already exist — do not remove those):

```nix
    "quickshell/widgets/components/Lock-dark.qml" = lockVariant "dark" ./components/LockDark.qml;
    "quickshell/widgets/components/Lock-light.qml" = lockVariant "light" ./components/LockLight.qml;
```

Remove any existing single `"quickshell/widgets/components/Lock.qml" = ...;` entry from `xdg.configFile` — that path becomes a runtime symlink instead, not a home-manager-managed file (same reasoning as Task 2's fix: a path can't be both home-manager-managed and runtime-swapped without a collision).

Add a default-symlink activation step, following the same pattern as Tasks 4/5/6:

```nix
  home.activation.quickshellLockDefault = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/quickshell/widgets/components/Lock-dark.qml" "${config.xdg.configHome}/quickshell/widgets/components/Lock.qml"
  '';
```

Do not add, modify, or remove the `systemd.user.services.quickshell-widgets` block, and do not restart it from this task's darkman scripts — the assumption (to state explicitly in your report) is that quickshell's lock IPC call (`quickshell ipc -c widgets call lock lock`) loads `Lock.qml` fresh from disk on each invocation rather than caching it in the long-running daemon process, so a plain symlink swap is sufficient without touching the running bar/daemon at all. If you find evidence this assumption is wrong (e.g. quickshell explicitly documents caching QML component sources), say so in your report as a concern rather than adding a restart — restarting the daemon is out of scope per the user's explicit instruction not to manage the bar.

- [ ] **Step 2: Add darkman scripts**

Edit `modules/home-manager/darkman.nix`:

```nix
      quickshell-lock-theme = ''
        ${pkgs.coreutils}/bin/ln -sf "${config.xdg.configHome}/quickshell/widgets/components/Lock-dark.qml" "${config.xdg.configHome}/quickshell/widgets/components/Lock.qml"
      '';
```
(add to `darkModeScripts`; light variant with `Lock-light.qml`, added to `lightModeScripts`. No systemd restart call — see Step 1's note.)

- [ ] **Step 3: Verify**

Run: `nix flake check`
Expected: no errors.

Run: `home-manager switch --flake .#personal`
Then: `darkman set dark && cat ~/.config/quickshell/widgets/components/Lock.qml | grep -o '#[0-9A-Fa-f]\{6\}' | head -3` — expect dark-palette hex values.
Then: `darkman set light` and repeat — expect light-palette hex values, with no visible disruption to the running bar/widgets (confirm the bar's own process, e.g. `pgrep -f 'quickshell -c widgets'`, is not restarted by either command).
Then lock the screen (`swaymsg exec 'quickshell ipc -c widgets call lock lock'`) and confirm the currently-symlinked variant is what's shown.

- [ ] **Step 4: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/default.nix modules/home-manager/darkman.nix
git commit -m "feat: switch quickshell lockscreen colors with darkman (bar untouched)"
```

---

## Post-plan manual check

After all seven tasks: leave the machine running past an actual sunset or sunrise once, and confirm the targets that actually switch live — gtk (dconf-only), mako, tofi, and the quickshell lockscreen — flip without any manual `darkman set` call. This is the one thing none of the per-task steps can verify synchronously. Note: waybar and swaync were ultimately dropped from darkman (their modules exist but are dormant/unwired on `personal`), and the quickshell bar/widget shell was excluded entirely from theming, so neither is part of this check.
