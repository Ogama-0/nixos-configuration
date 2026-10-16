# Single implementation of the @token@ substitution used to theme the
# Quickshell QML. Called by the home-manager quickshell module (passing home
# paths) and by modules/nixosconf/greetd.nix (passing Nix store paths, because
# the greeter user cannot read /home).
#
# `colors` is one base16 palette attrset out of modules/lib/theme-colors.nix -
# the same source for the bar, the lock and the greeter surfaces.
{ colors
, laserColor
, lockscreenImage
, systemctlBin
, corptaFontPath
  # Status-widget tokens. Defaulted so greetd.nix and the lockVariant helper,
  # which never render StatusPanel.qml, do not have to pass them - a required
  # argument here would break both callers. The colour defaults are the Horizon
  # dark values; the quickshell module always passes explicit
  # polarity-correct ones, because Horizon puts teal at base0C in dark but
  # base0E in light, so no single base16 slot means "up" in both schemes.
, statusApiUrl ? ""
, metricsApiUrl ? ""
, upColor ? "#FF24A8B4"
, degradedColor ? "#FFEFB993"
, downColor ? "#FFE93C58"
  # base04 is legible on the dark ground (6.5:1) but only 2.5:1 on the light
  # one, which is too low for the 11px latency column. The quickshell module
  # passes a polarity-correct value; this default preserves the dark-ground
  # behaviour for callers that never render these tokens.
, mutedColor ? "#FF${colors.base04}"
  # Space-separated directory names under assets/wallpaper that the picker
  # draws from, substituted into Wallpaper.qml's find. Defaulted so
  # modules/nixosconf/greetd.nix, which renders no Wallpaper.qml, needs no
  # change. The quickshell module passes "dark both" or "light both".
, wallpaperDirs ? "both"
  # Bar-module capsule colours. Not a single base16 slot: the plate is the
  # light one and the outline the dark one, and those swap between the
  # variants (dark base05 is near-white, light base05 is near-black). The
  # quickshell module passes polarity-correct values; these defaults are the
  # dark ones, for the callers that render no bar.
  # Absolute path to swaymsg. PATH is not dependable inside the systemd user
  # service, which is why @systemctlBin@ exists too.
, swaymsgBin ? "swaymsg"
, capsuleFill ? "#F2${colors.base05}"
, capsuleInk ? "#FF${colors.base00}"
}:
builtins.replaceStrings
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
    "@glassBg@"
    "@glassBorder@"
    "@corptaFontPath@"
    "@statusApiUrl@"
    "@metricsApiUrl@"
    "@upColor@"
    "@degradedColor@"
    "@downColor@"
    "@unknownColor@"
    "@panelBg@"
    "@panelBorder@"
    "@nameColor@"
    "@mutedColor@"
    "@wallpaperDirs@"
    "@swaymsgBin@"
    "@capsuleFill@"
    "@capsuleInk@"
  ]
  [
    "#B3${colors.base00}"
    "#33${colors.base05}"
    "#FF${colors.base05}"
    "#CC${colors.base04}"
    "#22${colors.base03}"
    "#FF${colors.base0D}"
    "#FF${colors.base00}"
    systemctlBin
    lockscreenImage
    laserColor
    "#FF${colors.base0B}"
    "#FF${colors.base08}"
    "#66${colors.base00}"
    "#59${colors.base05}"
    corptaFontPath
    statusApiUrl
    metricsApiUrl
    upColor
    degradedColor
    downColor
    "#FF${colors.base03}"
    # More opaque than @cardBg@'s #B3, and for a different reason than that
    # token's consumers need. The clock and calendar render 26-64px type, so
    # 70% over wallpaper is fine for them; this panel's latency column is
    # 11px muted text needing 4.5:1. Wallpaper brightness is not fixed - it
    # is user-switchable via the picker - so the alpha is chosen for the
    # worst case rather than the current image: 90% keeps that column legible
    # even over a white backdrop (4.70:1), where 85% drops to 3.93:1.
    "#E6${colors.base00}"
    "#33${colors.base05}"
    "#FF${colors.base05}"
    mutedColor
    wallpaperDirs
    swaymsgBin
    capsuleFill
    capsuleInk
  ]
