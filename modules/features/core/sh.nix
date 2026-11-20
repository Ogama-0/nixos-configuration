{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.core.sh.enable = lib.mkEnableOption "the fish shell, its prompt and aliases";
    };
in
{
  flake.featureModules.nixos.sh = sharedOptions;

  flake.featureModules.home.sh =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.core.sh.enable ({
        home.packages =
          with pkgs;
          [

            # App Tool Cli
            xsel
            killall
            openssl
            lsof
            dig
            trash-cli
            zip
            unzip
            ascii
            eza
            tokei
            bat
            fzf
            zoxide
            tlrc
            xsel
            file
            dust
            direnv

            # App Tool Tui
            btop
            fastfetch

          ]
          ++ lib.optionals (!config.ogama.identity.isEpita) [
            #only non epita

            # App Tool Cli

            brightnessctl
            power-profiles-daemon
            zenity
            nmap
            ripgrep
            ookla-speedtest

            # App Tool Tui
            rocmPackages.rocm-smi # for amd gpu to btop

            # Dev
            gh-dash
            gccgo14 # C
            gnumake
            vulkan-tools
            pciutils
            (linux-manual.overrideAttrs (old: {
              preBuild = (old.preBuild or "") + ''
                export srctree=$PWD
              '';
            }))
            man-pages
            man-pages-posix
          ];

        programs.man = lib.mkIf (!config.ogama.identity.isEpita) {
          enable = true;
          man-db.enable = false;
          mandoc.enable = true;
        };

        home.extraProfileCommands = lib.mkBefore ''
          for dir in "$out"/share/man/man*; do
            if [ -L "$dir" ]; then
              target=$(readlink -f "$dir")
              rm "$dir"
              mkdir "$dir"
              # -exec + chunks the arguments: a plain glob overflows ARGV here.
              find "$target"/ -mindepth 1 -maxdepth 1 -exec ln -s -t "$dir" {} +
            fi
          done
        '';

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
            ll = "ls -lhaF";
            llo = "ls -lhaF -s oldest";
            tree = "ls -T";
            tp = "trash-put";
            tl = "trash-list";
            tempt = "trash-empty";
            rm = "#";

          }
          // lib.optionalAttrs (!config.ogama.identity.isEpita) {
            #only non epita

            cps = "rsync --compress --verbose --recursive --human-readable --partial --progress --archive";
            wl = "nmcli device wifi list";
            ws = "nmcli device wifi rescan";
            wcn = "nmcli device wifi connect";
            wscn = "nmcli device wifi rescan && nmcli device wifi connect";
            wsl = "nmcli device wifi rescan && nmcli device wifi list";
            shutdown = "hollywood";
            c = "cargo";
            cr = "cargo run";
          }
          // lib.optionalAttrs (config.ogama.identity.isEpita) {
            # only on epita
            gf = "gcc -std=c99 -pedantic -Werror -Wall -Wextra -Wvla";
          };

          functions = {
            fish_greeting = ''
              clear
            '';

            accept-autosuggestion-or-backtick = ''
              if commandline --showing-suggestion
                commandline -f accept-autosuggestion
              else
                commandline -i \`
              end
            '';

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
          settings.hostname.ssh_symbol = " ";
        };

        programs.zoxide = {
          enable = true;
          enableFishIntegration = true;
          options = [ "--cmd cd" ];
        };

        home.sessionVariables.SHELL = lib.getExe pkgs.fish;

        home.sessionVariables._ZO_DATA_DIR =
          if config.ogama.identity.isEpita then
            "${config.ogama.identity.homePath}/afs/.local/share/zoxide"
          else
            "${config.ogama.identity.homePath}/.local/share/zoxide";

        programs.direnv = {
          enable = true;
          silent = true;
          nix-direnv.enable = true;
        };
      });
    };
}
