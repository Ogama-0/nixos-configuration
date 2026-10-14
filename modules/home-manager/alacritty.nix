{ pkgs, lib, config, ... }:
let
  colorsPath = "${config.xdg.configHome}/alacritty/colors.toml";
  alacrittyColors = import ../lib/alacritty-colors.nix { inherit pkgs; };
in
{
  programs.alacritty = {
    enable = true;

    settings = {
      general = {
        # colors.toml is rewritten at runtime by darkman and so must NOT be
        # managed by xdg.configFile - a managed path is a read-only store
        # symlink. It is seeded by the activation script below, following the
        # same pattern as darkmanTimezoneSync.
        import = [ colorsPath ];
        live_config_reload = true;
      };

      window = { decorations = "buttonless"; };

      font = {
        size = 13.5;
        normal.family = "JetBrainsMonoNerdFont";
        bold.family = "JetBrainsMonoNerdFont";
        italic.family = "JetBrainsMonoNerdFont";
      };

      terminal.shell = { program = "fish"; };
    };
  };

  # Seed ONLY when the file is missing. darkman owns the steady state, and an
  # unconditional write here would force dark on every activation - flipping a
  # daytime desktop to dark until darkman's restart corrected it, and leaving
  # it dark for good if that restart ever failed (it is `|| true`).
  home.activation.alacrittyColorsDefault =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${pkgs.coreutils}/bin/mkdir -p "${config.xdg.configHome}/alacritty"
      if [ ! -e "${colorsPath}" ]; then
        run ${pkgs.coreutils}/bin/install -m 644 ${alacrittyColors.dark} "${colorsPath}"
      fi
    '';
}
