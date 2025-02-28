{ pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    eza
    lazygit
    tokei
    bat
    fzf
    gh-dash
    zoxide
    delta
    tlrc
    zenity
  ];

  programs.kitty = {
    enable = true;

    settings = {
      confirm_os_window_close = 0;
      enable_audio_bell = "no";
      macos_option_as_alt = "left";
    };

    shellIntegration = {
      mode = "enabled";
      enableFishIntegration = true;
    };

    font = {
      name = "CaskaydiaCoveNerdFont";
      size = 13;
    };

    extraConfig = ''
      disable_ligatures never
      shell fish
    '';
  };

  programs.fish = {
    enable = true;

    shellAliases = {
      ls = "${lib.getExe pkgs.eza} --color=auto --icons=auto --hyperlink";
      cat = "${lib.getExe pkgs.bat}";
    };

    shellAbbrs = {
      ll = "ls -lhaF";
      tree = "ls -T";
      ghd = "gh-dash";
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

      init-tp = ''
        set repository_link $argv[1]
        set tree $argv[2]
        set tp_name $argv[3]
        python $PATH_SCRIPTS/init-tp.py $repository_link $tree $tp_name
      '';

      wgup = ''
        set confname oscar
        set devconfname oscar-dev
        set backupconfname backup
        set devbackupconfname backup-dev

        # Correction de la déclaration des options dans argparse
        argparse d/dev b/backup -- $argv

        if set -q _flag_dev
          if set -q _flag_backup
            sudo systemctl start wg-quick-$devbackupconfname # Mode développement + backup
          else
            sudo systemctl start wg-quick-$devconfname # Mode développement seul
          end
        else
          if set -q _flag_backup
            sudo systemctl start wg-quick-$backupconfname # Mode backup seul
          else
            sudo systemctl start wg-quick-$confname # Mode normal
          end
        end
        sudo mount -t cifs //192.168.10.51/general_storage $PATH_NAS -o username=oscar,password=mdpelo,uid=$(id -u),gid=$(id -g)
      '';

      wgdn = ''

        sudo umount $PATH_NAS/
        # Récupérer la configuration WireGuard active
        set confname (sudo wg | grep interface | sed 's/.* //')

        # Vérifier si une configuration est active
        if test -n "$confname"
          sudo systemctl stop wg-quick-$confname
          echo "Configuration '$confname' arrêtée avec succès."
        else
          echo "Aucune configuration WireGuard active trouvée."
        end
      '';

      togglewg = ''
        set output (sudo wg)
        if test -n "$output"
          wgdn
        else
          wgup
        end
      '';

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
