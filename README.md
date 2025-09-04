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

<details>
  <summary> personal </summary>

  - add a TTY login menu
  - fix the background
  - fix the swaylock troll
</details>

<details>
  <summary> server </summary>
  
  - immich
  - use hdd and ssd disks
</details>

