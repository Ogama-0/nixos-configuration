# NixOs-configuration
My personal config NixOs


## Structure
- `assets`: images for the nix configurations
- `scripts`: Shell scripts
- `hosts`: Profiles configuration
  - `<profile>`: Bases configuration for a specific profile
    - `configuration.nix`: Bases for NixOS configuration
    - `<profile>.nix`: Bases for Home Manager config
    - `hardware-configuration`: Device-specific settings 
- `modules`: Configurations parts
	- `home-manager`: Home Manager related configurations
    - `display`: Window manager related configurations
	- `nixos`: NixOS related configurations

## Switch to another profile
```
nix run nixpkgs#home-manager -- switch --flake .#<profile>
```

- `personal`: Profile for my main computer
- `oserv`: Profile for my server
- `epita`: Profile for school computer
- `epita-light`: Profile for school computer designed to build fast

## TODO :

### personal
- add a TTY login menu
- switch background every X second or when you switch from one desktop to another
- search zellij 

### server
- build a web-site for ogama.me
- build a intenral API to for connect qbtorrent jellyfin and a web-UI

# Templates : 
```
nix flake init --template github:/ogama-0/nixos-configuration#<template>
```
###Templates :
- ``python`` : template for blank python project
- ``c`` : template for blank c project
- ``epita-c`` : template for epita practical in c
- ``asm68k``: template for blank asm68k project
