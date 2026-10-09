# Single implementation of the @token@ substitution used to theme the
# Quickshell QML. Called by the home-manager quickshell module (passing home
# paths) and by modules/nixosconf/greetd.nix (passing Nix store paths, because
# the greeter user cannot read /home).
#
# `colors` is one base16 palette attrset: either config.lib.stylix.colors for
# the bar, or a variant out of modules/lib/theme-colors.nix for the lock and
# greeter surfaces.
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
    "#B3${colors.base00}"
    "#33${colors.base05}"
    "#FF${colors.base05}"
    "#FF${colors.base04}"
  ]
