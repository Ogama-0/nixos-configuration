# NumberPad 2.0 on the ZenBook UX3405CA's touchpad (ASUF1415:00 2808:0224).
#
# This used to run mohamed-badaoui/asus-touchpad-numpad-driver, which cannot
# drive this hardware for two independent reasons:
#
#   1. It matches only touchpad names starting with ASUE or ELAN, so detection
#      failed outright with "Can't find touchpad (code: 0)".
#   2. Its backlight write is a single hand-built I2C-HID SET_REPORT pushed raw
#      at address 0x15 with `i2ctransfer -f`. i2c_hid owns this device, so the
#      write is accepted by the bus and never reaches the firmware; and even
#      over the correct transport, one write does not light an ASUF1415 panel.
#
# asus-linux-drivers/asus-numberpad-driver is the maintained successor and
# handles both: it recognises ASUF, sends the report through HIDIOCSFEATURE on
# the touchpad's hidraw node (falling back to i2c), and crucially sends the
# two-step 0x60-then-0x01 sequence this model needs to turn the panel on.
# Verified by hand on this machine: feature report 0x0d with payload
# 14 03 <value> ad, values 0x60 then 0x01, lights the numpad; 0x00 clears it.
# Report 0x0d is a 4-byte vendor feature report in this device's HID
# descriptor, which is why the payload is 5 bytes including the id.
{
  inputs,
  pkgs,
  lib,
  ...
}:
{
  imports = [ inputs.asus-numberpad-driver.nixosModules.default ];

  hardware.asus-numberpad-driver = {
    enable = true;

    # The upstream module defaults this to `pkgs.asus-numberpad-driver`, which
    # only exists if you apply its overlay. This repo hands a prebuilt `pkgs`
    # to nixosSystem, so `nixpkgs.overlays` set from a module is inert — take
    # the package straight off the flake instead. Its nixpkgs follows ours.
    package = inputs.asus-numberpad-driver.packages.${pkgs.stdenv.hostPlatform.system}.default;

    # Upstream's own device table maps ASUF1415:00 2808:0224 / UX3405CA to this
    # layout (laptop_touchpad_numberpad_layouts.csv).
    layout = "up5401ea";

    wayland = true;

    # The driver exits non-zero if it cannot connect to the Wayland display,
    # and upstream's default here is the literal "wayland-0" — but sway hands
    # out wayland-1 on this machine. Inherit the session's real value from the
    # systemd user environment rather than hardcoding a guess that silently
    # kills the service the next time the number changes.
    ignoreWaylandDisplayEnv = true;
  };

  # Upstream pipes both streams to /dev/null, which throws away any Python
  # traceback. Logging proper goes to the journal via JournalHandler anyway, so
  # keeping stderr costs nothing and makes a crash legible.
  systemd.user.services.asus-numberpad-driver.serviceConfig.StandardError = lib.mkForce "journal";

  # The backlight is driven through the touchpad's hidraw node, which is
  # root-owned 0600 by default. Upstream ships udev rules only for power-supply
  # and external-keyboard handling, so without this the driver — which runs as
  # a *user* service — cannot open the node, silently falls back to the i2c
  # path that does nothing here, and the panel stays dark.
  #
  # Matched on the parent HID device's bus:vendor:product rather than on
  # hidraw0, whose number is not stable. This does let anything running as
  # ogama read raw touchpad reports, which is the same trade the `input` group
  # already makes for /dev/input/event*.
  services.udev.extraRules = ''
    SUBSYSTEM=="hidraw", KERNELS=="0018:2808:0224.*", GROUP="input", MODE="0660"
  '';

  # input for /dev/input/event* and the hidraw node above, i2c for the fallback
  # transport, uinput for the virtual keyboard the driver types through. The
  # i2c and uinput groups come from hardware.{i2c,uinput}.enable, which the
  # upstream module turns on; `input` it creates itself.
  users.users.ogama.extraGroups = [
    "input"
    "i2c"
    "uinput"
  ];
}
