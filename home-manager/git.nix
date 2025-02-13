{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    lfs.enable = true;

    userName = "Oscar Cornut";
    userEmail = "oscar.cornut@gmail.com";

    aliases = {
      ui = "!lazygit";

      pu = "push";
      put = "push --follow-tags";
      s = "status";
      ss = "status --short";
      cm = "commit --message";
      ca = "commit --amend";
    };

    ignores = [ ".direnv/" "result" ];

    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;

      pull.rebase = true;
    };
    difftastic.enable = true;
  };

  programs.gh.enable = true;
}
