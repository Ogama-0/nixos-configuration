{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    lfs.enable = true;

    userName = "ogama";
    userEmail = "oscar.cornut@gmail.com";

    aliases = {
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
