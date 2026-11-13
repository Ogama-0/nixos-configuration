{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.dev.vim.enable = lib.mkEnableOption "vim, as the fallback editor";
    };
in
{
  flake.featureModules.nixos.vim = sharedOptions;

  flake.featureModules.home.vim =
    { config, lib, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.dev.vim.enable (
        {

          programs.vim = {
            enable = true;

            plugins = with pkgs.vimPlugins; [
              vim-sensible
              onedark-vim
              vim-wakatime
            ];

            settings = {
              background = "dark";
              expandtab = true;
              hidden = true;
              history = 1000;
              ignorecase = true;
              smartcase = true;
              mouse = "a";
              number = true;
              shiftwidth = 4;
              tabstop = 4;
            };

            extraConfig = ''
              let g:wakatime_CLIPath = '${lib.getExe pkgs.wakatime-cli}'

              set termguicolors
              colorscheme onedark

              set showmatch
              set matchtime=2
              set cursorline
              set hlsearch
              set scrolloff=5
              set splitbelow
              set splitright
              set wildmode=longest:full,full
              set clipboard=unnamedplus
            '';
          };
        }
      );
    };
}
