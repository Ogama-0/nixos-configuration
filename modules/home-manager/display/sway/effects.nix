# SwayFX eye candy: rounded corners and window shadows.
#
# None of these are typed options in home-manager's sway module - swayfx is a
# fork, so its directives go through extraConfig as literal config lines. The
# let block below is the surface you edit: change a number, rebuild.
#
# The package swap that makes these directives valid lives in ./default.nix.
# Animations are NOT available: they are still only on swayfx's roadmap.
{
  ...
}:

let
  # Window corner rounding, in pixels. smart_corner_radius keeps a lone
  # fullscreen-ish window square, which is what you want with border 0.
  cornerRadius = 8;

  shadow = {
    enable = true;
    blurRadius = 20; # 0 - 99
    offset = "0 2"; # x y
    color = "#0000007F";
    inactiveColor = "#00000050";
  };

  # Blur only shows through transparent windows and costs GPU time, so it
  # ships off. Flip enable to true when you want it.
  blur = {
    enable = false;
    passes = 2; # 0 - 10
    radius = 5; # 0 - 10
  };

  onOff = b: if b then "enable" else "disable";
in
{
  wayland.windowManager.sway.extraConfig = ''
    # --- swayfx effects (modules/home-manager/display/sway/effects.nix) ---
    corner_radius ${toString cornerRadius}
    smart_corner_radius enable

    shadows ${onOff shadow.enable}
    shadows_on_csd disable
    shadow_blur_radius ${toString shadow.blurRadius}
    shadow_offset ${shadow.offset}
    shadow_color ${shadow.color}
    shadow_inactive_color ${shadow.inactiveColor}

    blur ${onOff blur.enable}
    blur_xray disable
    blur_passes ${toString blur.passes}
    blur_radius ${toString blur.radius}
  '';
}
