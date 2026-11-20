{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.core.git.enable = lib.mkEnableOption "git, signed with the shared identity";
    };
in
{
  flake.featureModules.nixos.git = sharedOptions;

  flake.featureModules.home.git =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.core.git.enable ({
        programs.difftastic.enable = true;
        programs.git = {
          lfs.enable = true;
          enable = true;
          settings = {

            user = {
              name = config.ogama.identity.user;
              email = config.ogama.identity.mail;
            };
            alias = {
              ui = "!lazygit";
              ll = "log --graph --oneline";
              lla = "log --graph --oneline --all";
              pu = "push";
              put = "push --follow-tags";
              pute = "push --follow-tags";
              s = "status";
              ss = "status --short";
              cm = "commit --message";
              ca = "commit --amend";
              aad = "add -A";
              pusht = "push --follow-tags";
            };
            extraConfig = {
              init.defaultBranch = if config.ogama.identity.isEpita then "master" else "main";
              push.autoSetupRemote = true;
              pull.rebase = true;
            };
          };

          ignores = [
            ".direnv/"
            "result"
          ];

        };

        programs.gh.enable = lib.mkIf (!config.ogama.identity.isEpita) true;
      });
    };
}
