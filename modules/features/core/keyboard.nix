{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.core.keyboard.enable = lib.mkEnableOption "keyboard layout and key repeat";
    };
in
{
  flake.featureModules.nixos.keyboard = sharedOptions;

  flake.featureModules.home.keyboard =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.core.keyboard.enable {
        wayland.windowManager.sway = {
          config = {
            input = {
              "type:keyboard" = {
                xkb_options = "caps:escape";

                # "French (US)": includes us(basic) unchanged, so every
                # unaccented keystroke — and `'` `"` ` ~ ^ — is exactly a plain
                # US layout, with the French set on AltGr as single chords
                # (AltGr+e é, +a à, +r è, +u ù, +c ç, Shift for the capital).
                # Dead keys exist only on AltGr. See
                # docs/superpowers/specs/2026-11-13-french-accents-qwerty-design.md.
                xkb_layout = "fr";
                xkb_variant = "us";
              };
            };
          };
        };
      };
    };
}
