cp ~/afs/.wakatime.cfg ~
nix run nixpkgs#home-manager -- switch --flake .#epita
i3-msg reload
