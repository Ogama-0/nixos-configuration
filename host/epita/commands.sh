#!/usr/bin/env sh
cp ~/afs/.wakatime.cfg ~
setxkbmap -option caps:escape
nix run nixpkgs#home-manager -- switch --flake .#epita
i3-msg reload
