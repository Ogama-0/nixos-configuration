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
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.core.git.enable (
        {
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

                tagarchi =
                  "!f(){ git add -A ; git commit -m 'autocommit'; git tag -ma archi-$(openssl rand -hex 4); git push --follow-tags; }; f";
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
                init.defaultBranch = "main";
                push.autoSetupRemote = true;

                pull.rebase = true;
              };
            };

            ignores = [ ".direnv/" "result" ];

          };

          programs.gh.enable = true;
        }
      );
    };
}
