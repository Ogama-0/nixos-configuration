{ pkgs, lib, ... }:
let script-path = ../../scripts;
in {
  home.packages = with pkgs; [
    xsel
    killall
    openssl
    fastfetch
    pkg-config
    brightnessctl

    # App Tool Cli
    trash-cli
    zip
    unzip
    ascii
    nmap
    ripgrep
    eza
    tokei
    bat
    fzf
    zoxide
    delta
    tlrc
    zenity
    xsel

    # App Tool Tui
    btop
    lazygit
    gh-dash

    # Dev related
    gccgo14 # C
    direnv
    gnumake

  ];

  programs.fish = {
    enable = true;

    shellAliases = {
      ls = "${lib.getExe pkgs.eza} --color=auto --icons=auto --hyperlink";
      cat = "${lib.getExe pkgs.bat}";
      imp = "${lib.getExe pkgs.kitty} icat";
    };

    shellAbbrs = {
      c = "cargo";
      cr = "cargo run";
      ll = "ls -lhaF";
      tree = "ls -T";
      ghd = "gh-dash";
      tp = "trash-put";
      tl = "trash-list";
      tempt = "trash-empty";
      tsempt = "trash-empty 10";
      # rm = "#";
      shutdown = "hollywood";
      stnow = "shutdown now";
      cacat = "bat";
      nhx = "hx /home/ogama/nixos-configuration";
      wl = "nmcli device wifi list";
      ws = "nmcli device wifi rescan";
      wcn = "nmcli device wifi connect";
      wscn = "nmcli device wifi rescan && nmcli device wifi connect";
      wsl = "nmcli device wifi rescan && nmcli device wifi list";
    };

    functions = {
      fish_greeting = ''
        set rdm (random 0 1)
        if test $rdm = 0 
          echo "salut caml c'est zizou"   
        else if test $rdm = 1
          echo "🐫🐫🐫🐫🐫vive caml🐫🐫🐫🐫🐫"
        end
      '';

      kijesui = "whoami";

      # init-tp = ''
      #   set repository_link $argv[1]
      #   set tree $argv[2]
      #   set tp_name $argv[3]
      #   python $PATH_SCRIPTS/init-tp.py $repository_link $tree $tp_name
      # '';

      wgup = builtins.readFile "${script-path}/fish/wgup.fish";

      wgdn = builtins.readFile "${script-path}/fish/wgdn.fish";

      togglewg = builtins.readFile "${script-path}/fish/togglewg.fish";

      cdtmp = ''
        set ash (openssl rand -hex 4)
        mkdir /tmp/$ash
        cd /tmp/$ash
      '';

      connectIphone = {
        body =
          "nmcli device wifi connect 'iPhone de Oscar' password 'ogama75?'";
      };

    };
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;

    settings.nix_shell = {
      format = "via [$symbol$state]($style) ";
      symbol = " ";
    };
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    options = [ "--cmd cd" ];
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  home.sessionVariables.DIRENV_LOG_FORMAT = "";

}
