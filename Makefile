NIX_FLAGS := --extra-experimental-features "nix-command flakes"

.DEFAULT_GOAL := help
.PHONY: help personal personal-hm oserv oserv-hm epita epita-light check update

help:
	@echo "make personal     NixOS + Home Manager switch, sudo (main desktop)"
	@echo "make personal-hm  Home Manager switch only, no sudo (main desktop)"
	@echo "make oserv        NixOS + Home Manager switch, sudo (home server, run on oserv itself)"
	@echo "make oserv-hm     Home Manager switch only, no sudo (home server, run on oserv itself)"
	@echo "make epita        Home Manager switch (EPITA computer)"
	@echo "make epita-light  Home Manager switch (EPITA computer, trimmed down)"
	@echo "make check        nix flake check"
	@echo "make update       nix flake update"

personal:
	nh os switch . -H personal

personal-hm:
	nh home switch . -c personal
	systemctl --user restart quickshell-widgets

oserv:
	nh os switch . -H oserv

oserv-hm:
	nh home switch . -c oserv

epita:
	cp ~/afs/.wakatime.cfg ~
	setxkbmap -option caps:escape
	nh home switch . -c epita
	i3-msg reload

epita-light:
	cp ~/afs/.wakatime.cfg ~
	setxkbmap -option caps:escape
	nh home switch . -c epita-light
	i3-msg reload

check:
	nix $(NIX_FLAGS) flake check

update:
	nix $(NIX_FLAGS) flake update
