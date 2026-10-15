{ pkgs, lib, config, ... }:
let
  themes = import ../../lib/zellij-theme.nix { inherit pkgs; };
  autoThemePath = "${config.xdg.configHome}/zellij/themes/auto.kdl";
in
{

  programs.zellij = {
    enable = true;
    # enableFishIntegration = true;
  };

  xdg.configFile."zellij/config.kdl".source = ./config.kdl;
  xdg.configFile."zellij/layout/onbar.kdl".source = ./layout/nobar.kdl;

  # palette-dark and palette-light, what config.kdl's theme_dark/theme_light
  # name and what darkman flips a running session between. `themes/` is
  # zellij's default theme_dir, so nothing else is needed to find them.
  xdg.configFile."zellij/themes/palette.kdl".source = themes.both;

  # palette-auto, the theme a new session starts in. Rewritten at runtime by
  # darkman and so NOT managed by xdg.configFile - a managed path is a
  # read-only store symlink - and seeded only when missing, for the same
  # reason alacritty's colors.toml is (see modules/home-manager/alacritty.nix).
  home.activation.zellijAutoThemeDefault =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${pkgs.coreutils}/bin/mkdir -p "${config.xdg.configHome}/zellij/themes"
      if [ ! -e "${autoThemePath}" ]; then
        run ${pkgs.coreutils}/bin/install -m 644 ${themes.auto "dark"} "${autoThemePath}"
      fi
    '';
}
