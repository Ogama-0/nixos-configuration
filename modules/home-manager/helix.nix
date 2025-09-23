{ pkgs, inputs, config, ... }:

{
  programs.helix = {
    enable = true;
    defaultEditor = true;

    extraPackages = with pkgs; [
      wakatime
      inputs.wakatime-ls.packages."x86_64-linux".wakatime-ls
      # Nix Related
      nil
      nixfmt-classic

      # Markdown
      marksman

      # C related
      clang-tools

      # Web related
      vscode-langservers-extracted
      typescript-language-server
      svelte-language-server

      # Python
      ruff
      python312Packages.jedi-language-server
      python312Packages.python-lsp-server
    ];
    ignores = [
      "*.png"
      "*.gif"
      "*.mcmeta"
      "*.eot"
      "*.webp"
      "*.ttf"
      "*.woff"
      "*.jpg"
      ".direnv/*"
    ];

    settings = {
      theme = "horizon-dark";

      editor = {
        auto-format = true;
        auto-save = true;
        mouse = false;
        bufferline = "multiple";
        file-picker.hidden = false;

        end-of-line-diagnostics = "hint";

        inline-diagnostics = {
          cursor-line = "hint";
          other-lines = "error";
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
        lsp = { display-inlay-hints = true; };
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
        rust-analyzer.config = { check.command = "clippy"; };
      };

      language = [
        {
          name = "nix";
          auto-format = true;
          formatter = { command = "nixfmt"; };
          language-servers = [ "nil" "wakatime" ];
        }
        {
          name = "python";
          auto-format = false;
          language-servers = [ "ruff" "jedi" "pylsp" "wakatime" ];
        }
        {
          name = "rust";
          auto-format = true;
          language-servers = [ "rust-analyzer" "wakatime" ];
        }
        {
          name = "markdown";
          language-servers = [ "marksman" ];
        }
        {
          name = "ocaml";
          auto-format = true;
          language-servers = [ "ocamllsp" "wakatime" ];
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
          language-servers = [ "clangd" "wakatime" ];
          auto-format = false;
          formatter = { command = "clang-format"; };
        }
        {
          name = "html";
          auto-format = true;
          language-servers = [ "vscode-html-language-server" "wakatime" ];
        }
        {
          name = "css";
          auto-format = true;
          language-servers = [ "vscode-css-language-server" "wakatime" ];
        }
        # {
        #   name = "asm";
        #   #   file-types = [ "s" "asm" ];
        #   #   scope = "source.asm";
        #   #   comment-tokens = ";";
        #   #   auto-format = false;
        #   language-servers = [ "wakatime" ];
        # }
      ];
    };
  };
}
