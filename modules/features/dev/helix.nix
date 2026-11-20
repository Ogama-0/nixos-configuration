{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.dev.helix.enable = lib.mkEnableOption "the helix editor, themed by darkman";
    };
in
{
  flake.featureModules.nixos.helix = sharedOptions;

  flake.featureModules.home.helix =
    {
      pkgs,
      inputs,
      config,
      lib,
      ...
    }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.dev.helix.enable (
        let
          autoThemePath = "${config.xdg.configHome}/helix/themes/auto.toml";
        in
        {
          programs.helix = {
            enable = true;
            defaultEditor = true;

            extraPackages =
              with pkgs;
              [
                wakatime-cli
                inputs.wakatime-ls.packages.${pkgs.system}.wakatime-ls

                # Nix Related
                nil
                nixfmt

                # Markdown
                marksman
              ]
              ++ lib.optionals (!config.ogama.identity.isEpita) [
                # Python
                ruff
                python312Packages.jedi-language-server
                python312Packages.python-lsp-server

                # Web related
                vscode-langservers-extracted
                typescript-language-server
                svelte-language-server

                # C related
                clang-tools
                # assembly
                asm-lsp
              ];
            ignores = [
              "*.gif"
              "*.mcmeta"
              "*.eot"
              "*.webp"
              "*.ttf"
              "*.woff"
              "*.jpg"
              ".direnv/*"
              ".cache/*"
            ];

            settings = {
              # Stable name; the body is swapped by darkman. See autoThemePath above.
              theme = "auto";

              editor = {
                auto-format = true;
                auto-save = true;
                mouse = false;
                bufferline = "multiple";
                file-picker.hidden = false;

                end-of-line-diagnostics = "hint";

                inline-diagnostics = {
                  cursor-line = "hint";
                  other-lines = "warning";

                };

                indent-guides = {
                  render = true;
                  characters = "╎";
                };

                cursor-shape = {
                  insert = "bar";
                  normal = "block";
                  select = "underline";
                };
                lsp = {
                  display-inlay-hints = true;
                };
                search = {
                  smart-case = false;
                };
              };

              keys = {
                normal = {
                  up = "no_op";
                  down = "no_op";
                  left = "no_op";
                  right = "no_op";
                  A-u = ":toggle lsp.display-inlay-hints";

                  "space" = {
                    "space" = ":toggle lsp.display-inlay-hints";
                    f = "file_picker_in_current_directory";
                    F = "file_picker";
                  };
                };
              };
            };

            languages = {
              language-server = {
                wakatime.command = "wakatime-ls";
                rust-analyzer.config = {
                  check.command = "clippy";
                };
              };

              language = [
                {
                  name = "nix";
                  auto-format = true;
                  formatter = {
                    command = "nixfmt";
                  };
                  language-servers = [
                    "nil"
                    "wakatime"
                  ];
                }
                {
                  name = "python";
                  auto-format = false;
                  language-servers = [
                    "ruff"
                    "jedi"
                    "pylsp"
                    "wakatime"
                  ];
                }
                {
                  name = "r";
                  auto-format = true;
                  language-servers = [
                    "R"
                    "wakatime"
                  ];
                }
                {
                  name = "rmarkdown";
                  auto-format = true;
                  language-servers = [
                    "R"
                    "wakatime"
                  ];
                }
                {
                  name = "latex";
                  auto-format = false;
                  language-servers = [
                    "texlab"
                    "wakatime"
                  ];
                }
                {
                  name = "rust";
                  auto-format = true;
                  language-servers = [
                    "rust-analyzer"
                    "wakatime"
                  ];
                }
                {
                  name = "markdown";
                  language-servers = [ "marksman" ];
                }
                {
                  name = "ocaml";
                  auto-format = true;
                  language-servers = [
                    "ocamllsp"
                    "wakatime"
                  ];
                }
                {
                  name = "javascript";
                  auto-format = true;
                  language-servers = [
                    "typescript-language-server"
                    "vscode-eslint-language-server"
                    "wakatime"
                  ];
                }
                {
                  name = "c";
                  language-servers = [
                    "clangd"
                    "wakatime"
                  ];
                  auto-format = true;
                  formatter = {
                    command = "clang-format";
                  };
                }
                {
                  name = "html";
                  auto-format = true;
                  language-servers = [
                    "vscode-html-language-server"
                    "wakatime"
                  ];
                }
                {
                  name = "css";
                  auto-format = true;
                  language-servers = [
                    "vscode-css-language-server"
                    "wakatime"
                  ];
                }
                {
                  name = "erlang";
                  auto-format = true;
                  language-servers = [
                    "elp"
                    "wakatime"
                  ];
                }
                {
                  name = "prolog";
                  auto-format = true;
                  language-servers = [
                    "swipl"
                    "wakatime"
                  ];
                }
                {
                  name = "bash";
                  auto-format = true;
                  language-servers = [
                    "bash-language-server"
                    "wakatime"
                  ];
                }
                {
                  name = "fish";
                  auto-format = true;
                  language-servers = [
                    "fish-lsp"
                    "wakatime"
                  ];
                }
                {
                  name = "gas";
                  auto-format = false;
                  file-types = [ "S" ];
                  language-servers = [
                    {
                      name = "asm-lsp";
                      except-features = [
                        "completion"
                        "diagnostics"
                        "signature-help"
                      ];
                    }
                    "wakatime"
                  ];
                }
                {
                  name = "nasm";
                  file-types = [

                    "asm"
                  ];
                  # scope = "source.asm";
                  # comment-tokens = ";";
                  language-servers = [ "wakatime" ];
                }
              ];
            };
          };

          home.activation.helixThemeDefault = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            run ${pkgs.coreutils}/bin/mkdir -p "${config.xdg.configHome}/helix/themes"
            if [ ! -e "${autoThemePath}" ]; then
              run ${pkgs.coreutils}/bin/install -m 644 \
                ${(import ../../../lib/helix-auto-theme.nix { inherit pkgs; }) "dark"} \
                "${autoThemePath}"
            fi
          '';
        }
      );
    };
}
