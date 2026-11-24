# Disables PipeWire's X11 bell module, which segfaults the whole audio daemon
# whenever Xwayland goes away.
#
# When the X display dies - session teardown, or Xwayland restarting across a
# suspend/resume - Xlib calls the module's I/O error handler twice. The second
# call destroys an event source the first one already removed, so pipewire
# takes a SIGSEGV in loop_destroy_source and the daemon dies outright:
#
#   #0  loop_destroy_source        (libspa-support.so + 0x8cac)
#   #1  x11_io_error_exit_handler  (libpipewire-module-x11-bell.so + 0x2ad2)
#   #5  display_io                 (libpipewire-module-x11-bell.so + 0x25e9)
#
# That is not a cosmetic crash on this machine. Quickshell holds PipeWire
# objects for the bar's audio pane, and losing the daemon under it takes the
# shell down too (quickshell-mirror/quickshell#1435) - which, if the session
# happens to be locked at the time, leaves sway holding an abandoned
# ext-session-lock and painting its red fallback with no way to authenticate.
# See docs/superpowers/specs/2026-11-23-session-lock-robustness.md.
#
# The upstream fix is to make that teardown idempotent; it is not in the
# pipewire this nixpkgs pins. The module only plays the X11 bell through
# libcanberra, which nothing here uses, so turning it off costs nothing.
#
# `module.x11.bell` is pipewire's own documented knob: its stock pipewire.conf
# guards the module with `condition = [ { module.x11.bell = !false } ]`.
{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { config, lib, ... }:
    {
      options.ogama.system.pipewireX11BellFix.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.ogama.desktop.sway.enable;
        defaultText = lib.literalExpression "config.ogama.desktop.sway.enable";
        description = "work around the pipewire x11-bell crash on Xwayland teardown";
      };
    };
in
{
  flake.featureModules.nixos.pipewireX11BellFix =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.pipewireX11BellFix.enable {
        services.pipewire.extraConfig.pipewire."99-disable-x11-bell" = {
          "context.properties"."module.x11.bell" = false;
        };
      };
    };

  flake.featureModules.home.pipewireX11BellFix = sharedOptions;
}
