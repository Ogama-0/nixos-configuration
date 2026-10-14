# Shim over modules/lib/palette.nix - DO NOT edit colours here, edit palette.nix.
#
# Exists only to strip the leading `#`. Six consumers build colours as
# `"#FF${colors.base0D}"`, prepending `#` *and* an alpha byte for QML's
# #AARRGGBB form (see modules/lib/qml-theme.nix's token table), so they need
# the bare six hex digits. palette.nix stores `#RRGGBB` because that is what
# you can paste from a colour picker; this converts between the two.
let
  palette = import ./palette.nix;
  strip = builtins.mapAttrs (_: v: builtins.substring 1 6 v);
in
{
  dark = strip palette.dark.ui;
  light = strip palette.light.ui;
}
