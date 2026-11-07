NIX_FLAGS := --extra-experimental-features "nix-command flakes"

.DEFAULT_GOAL := help
.PHONY: help personal oserv epita epita-light check update

help:
	@echo "make personal     NixOS + Home Manager switch (main desktop)"
	@echo "make oserv        NixOS + Home Manager switch (home server, run on oserv itself)"
	@echo "make epita        Home Manager switch (EPITA computer)"
	@echo "make epita-light  Home Manager switch (EPITA computer, trimmed down)"
	@echo "make check        nix flake check"
	@echo "make update       nix flake update"

personal:
	nh os switch . -H personal

oserv:
	nh os switch . -H oserv

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
