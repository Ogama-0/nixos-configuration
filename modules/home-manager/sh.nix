{
  pkgs,
  lib,
  cfg,
  ...
}:
{
  home.packages = with pkgs; [
    xsel
    killall
    openssl
    fastfetch
    pkg-config
    brightnessctl

    power-profiles-daemon

    # App Tool Cli
    lsof
    dig
    immich-cli
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
    file
    dust
    ookla-speedtest
    # App Tool Tui
    btop
    rocmPackages.rocm-smi # for amd gpu to btop
    lazygit
    gh-dash
    pciutils

    # Dev related
    gccgo14 # C
    direnv
    gnumake
    vulkan-tools
    linux-manual
    man-pages
    man-pages-posix

  ];

  programs.fish = {
    enable = true;

    # Accept the autosuggestion with ` (falls back to inserting a real
    # backtick when there is nothing to accept).
    interactiveShellInit = ''
      bind \` accept-autosuggestion-or-backtick
      bind -M insert \` accept-autosuggestion-or-backtick
    '';

    shellAliases = {
      ls = "${lib.getExe pkgs.eza} --color=auto --icons=auto --hyperlink";
      cat = "${lib.getExe pkgs.bat}";
    };

    shellAbbrs = {
      gf = "gcc -std=c99 -pedantic -Werror -Wall -Wextra -Wvla";
      c = "cargo";
      cr = "cargo run";
      ll = "ls -lhaF";
      llo = "ls -lhaF -s oldest";
      tree = "ls -T";
      ghd = "gh-dash";
      tp = "trash-put";
      tl = "trash-list";
      tempt = "trash-empty";
      tsempt = "trash-empty 10";
      cps = "rsync --compress --verbose --recursive --human-readable --partial --progress --archive";
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
      # fish_greeting = ''
      #   set rdm (random 0 1)
      #   if test $rdm = 0
      #     echo "salut caml c'est zizou"
      #   else if test $rdm = 1
      #     echo "🐫🐫🐫🐫🐫vive caml🐫🐫🐫🐫🐫"
      #   end
      # '';
      fish_greeting = ''
        clear
      '';

      kijesui = "whoami";

      accept-autosuggestion-or-backtick = ''
        if commandline --showing-suggestion
          commandline -f accept-autosuggestion
        else
          commandline -i \`
        end
      '';

      # init-tp = ''
      #   set repository_link $argv[1]
      #   set tree $argv[2]
      #   set tp_name $argv[3]
      #   python $PATH_SCRIPTS/init-tp.py $repository_link $tree $tp_name
      # '';

      cdtmp = ''
        set ash (openssl rand -hex 4)
        mkdir /tmp/$ash
        cd /tmp/$ash
      '';

    };
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;

    settings.nix_shell = {
      format = "via [$symbol$state]($style) ";
      symbol = " ";
    };

    # starship's default ssh_symbol is U+1F310 GLOBE WITH MERIDIANS, an emoji -
    # and it renders as tofu in the terminal, because the fallback for that
    # codepoint does not land on a font that actually draws it there. It is not
    # simply missing: three installed fonts claim U+1F310, so adding an emoji
    # font would not fix it. This is the Nerd Font globe U+F0AC instead, which
    # comes from the same JetBrainsMono Nerd Font that already draws the git
    # branch icon - so it renders wherever the rest of the prompt does,
    # including on hosts carrying no emoji font at all.
    #
    # Only ever visible over SSH, which in practice means the oserv prompt.
    settings.hostname.ssh_symbol = " ";
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    options = [ "--cmd cd" ];
  };

  home.sessionVariables.SHELL = lib.getExe pkgs.fish;

  home.sessionVariables._ZO_DATA_DIR =
    if cfg.is-epita then
      "${cfg.home_path}/afs/.local/share/zoxide"
    else
      "${cfg.home_path}/.local/share/zoxide";

  programs.direnv = {
    enable = true;
    silent = true;
    nix-direnv.enable = true;

  };

}
