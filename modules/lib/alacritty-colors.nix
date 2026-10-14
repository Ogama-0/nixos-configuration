# The two alacritty colour files darkman swaps between at runtime. Imported by
# modules/home-manager/alacritty.nix (to seed the default and declare the
# import) and by modules/home-manager/darkman.nix (to install the right one on
# each sunrise/sunset).
#
# The values live in modules/lib/palette.nix under `<mode>.terminal` - edit
# them there, not here. This file only renders them as TOML.
{ pkgs }:
let
  palette = import ./palette.nix;

  renderGroup = name: g: ''
    [colors.${name}]
    black   = "${g.black}"
    red     = "${g.red}"
    green   = "${g.green}"
    yellow  = "${g.yellow}"
    blue    = "${g.blue}"
    magenta = "${g.magenta}"
    cyan    = "${g.cyan}"
    white   = "${g.white}"
  '';

  render = variant:
    let t = palette.${variant}.terminal; in
    pkgs.writeText "alacritty-colors-${variant}.toml" ''
      [colors.primary]
      background = "${t.background}"
      foreground = "${t.foreground}"

      ${renderGroup "normal" t.normal}
      ${renderGroup "bright" t.bright}
    '';
in
{
  dark = render "dark";
  light = render "light";
}
