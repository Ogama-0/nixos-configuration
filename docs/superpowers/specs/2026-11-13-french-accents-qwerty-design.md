# French accents on a QWERTY layout — design

2026-11-13 · small change · `modules/features/core/keyboard.nix`

## Intent and why

Oscar is French and types French regularly, but works on a US QWERTY layout
(physical keyboard and muscle memory both). Today `ogama.core.keyboard` pins
sway to `xkb_layout = "us"`, so é, à, è, ç and the rest have no key at all —
they have to come from somewhere outside the keyboard (copy-paste, a picker).
The goal is to make the French set typeable without disturbing a single
unaccented keystroke.

## Goals

- Every common French letter — é è à ù ç ê â î ô û ë ï ü œ æ — reachable in one
  chord, not a dead-key sequence.
- The unaccented layout stays byte-identical to the current `us`.
- `'` `"` `` ` `` `~` `^` keep their literal, immediate behaviour: no dead keys
  on the base levels. This is a programmer's keyboard first.

## Non-goals

- No relayout. Dvorak, bépo, Colemak and Ergo-L are all out of scope; the
  QWERTY base is a given, not a question.
- No custom xkb symbols file to maintain in this repo.

## Anti-goals

- Anything that makes typing a shell quote or a backtick cost an extra
  keystroke. That would be a net loss even if every accent got faster.
- A layout `greetd` doesn't understand. Password entry must not depend on this.

## Constraints

- `caps:escape` must survive — it is existing muscle memory.
- Right Alt is the AltGr/level3 switch, so it cannot simultaneously be a
  Compose key.
- Home Manager side only. `ogama.core.keyboard`'s NixOS half declares the
  option and configures nothing; the TTY console and the greeter
  (`modules/features/desktop/greeter.nix`) keep plain `us` deliberately.

## Approaches

There is no research on the best chord for a given accent — layout-optimisation
work (Ergo-L, bépo, carpalx) redesigns whole layouts by character frequency and
Fitts' law, which the non-goals rule out. The one applicable finding is that
dead keys beat one-key-per-accent only below ~4% diacritic density; French sits
at that line, which argues for per-key assignment.

1. **`us(altgr-intl)`** — dead keys moved onto AltGr. é = AltGr+e and
   ç = AltGr+comma are single chords, but è and à cost two (AltGr+`` ` ``
   then the letter). Reaches for Spanish and German, not French. Rejected:
   it is strictly worse than (2) for this use.
2. **`fr(us)` — "French (US)"** ← **chosen**. Upstream xkeyboard-config
   variant that `include`s `us(basic)` and hangs the French set off AltGr
   mnemonically. Satisfies all three goals exactly; nothing to maintain.
3. **Compose key** (`compose:ralt` or similar) — base layout untouched, covers
   all of Unicode, trivially memorable, but three sequential keys per accent
   instead of one chord, and it claims the right Alt that (2) needs.
   Rejected: slower on the characters that actually matter, and mutually
   exclusive with (2).

## The design

In `modules/features/core/keyboard.nix`, the sway `"type:keyboard"` input block
becomes:

```nix
xkb_options = "caps:escape";
xkb_layout = "fr";
xkb_variant = "us";
```

`xkb_options` is unchanged. The commented-out `home.keyboard` block and the
`# xkb_layout = "fr";` experiment are deleted — the question they were parked
on is now answered.

What that buys, all single chords, Shift giving the capital:

```
AltGr+e → é    AltGr+a → à    AltGr+r → è    AltGr+u → ù    AltGr+c → ç
AltGr+d → ê    AltGr+z → â    AltGr+o → ô    AltGr+k → î    AltGr+j → û
AltGr+f → ë    AltGr+i → ï    AltGr+h → ü    AltGr+p → œ    AltGr+s → æ
AltGr+y → ÿ    AltGr+[ ] → « »    AltGr+4 → € ¤    AltGr+5 → €
```

Dead keys still exist, but only on AltGr: AltGr+`` ` `` grave,
AltGr+6 circumflex, AltGr+' diaeresis. The base levels are plain `us`.

## Left to the builder

Nothing of substance. Verification: `nix flake check` plus
`nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath` (a
green check alone does not force the generated config text), then
`make personal-hm` and a real `AltGr+e` in a terminal. The file must be
`git add`ed before either command is believed.

## Verified

Both keymaps compiled with `xkbcli compile-keymap` (`--layout us` vs
`--layout fr --variant us`, both with `caps:escape`) and diffed level by level:

- 480 keys in each, same key set.
- **Zero** differences on the unshifted and shifted levels. `q`, `'`, `"`,
  `` ` ``, `~`, `^`, `,`, `/` and every other base keystroke are identical.
- 23 keys gain level-3/level-4 (AltGr) symbols where plain `us` had none.
- One real behavioural change: `<RALT>` goes from `Alt_R` to
  `ISO_Level3_Shift`. Unavoidable — it is what makes AltGr exist. No sway
  binding in this repo uses Alt, and left Alt is unaffected.

`nix flake check` passes and
`nix build .#homeConfigurations.personal.activationPackage` builds
(`/nix/store/jwxsqv33d7g3b61nxdnq3d371rfrs4x3-home-manager-generation`).
