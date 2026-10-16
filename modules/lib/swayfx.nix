# THE definition of the compositor the personal profile logs into.
#
# Two unrelated configurations need the exact same derivation and must not
# drift apart:
#   - modules/home-manager/display/sway, which writes ~/.config/sway/config
#     (including the swayfx-only directives in that module's effects.nix)
#   - modules/nixosconf/greetd.nix, whose greeter execs this binary by
#     absolute store path to start the session
# Home-manager and NixOS are separate configurations in flake.nix, so neither
# can read the other's options - hence this file.
#
# The wrapper flags mirror home-manager's own default for
# `wayland.windowManager.sway.package`: setting that option discards the
# `wrapperFeatures` option entirely, so the GTK wrapper (which fixes common
# issues with GTK 3 apps) has to be requested here.
pkgs:

pkgs.swayfx.override {
  withBaseWrapper = true;
  withGtkWrapper = true;
}
