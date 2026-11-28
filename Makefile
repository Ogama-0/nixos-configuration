NIX_FLAGS := --extra-experimental-features "nix-command flakes"

.DEFAULT_GOAL := help
.PHONY: help personal personal-hm personal-lenovo personal-lenovo-hm oserv oserv-hm epita epita-light check update

help:
	@echo "make personal          NixOS switch only, sudo (main desktop, ZenBook) -- does NOT switch Home Manager"
	@echo "make personal-hm       Home Manager switch only, no sudo (main desktop, ZenBook)"
	@echo "make personal-lenovo    NixOS switch only, sudo (old main desktop, Lenovo) -- does NOT switch Home Manager"
	@echo "make personal-lenovo-hm Home Manager switch only, no sudo (old main desktop, Lenovo)"
	@echo "make oserv        NixOS switch only, sudo (home server, run on oserv itself) -- does NOT switch Home Manager"
	@echo "make oserv-hm     Home Manager switch only, no sudo (home server, run on oserv itself)"
	@echo "make epita        Home Manager switch (EPITA computer)"
	@echo "make epita-light  Home Manager switch (EPITA computer, trimmed down)"
	@echo "make y13          Nixos switch only sudo (y13 server)"
	@echo "make y13-hm       Home Manager switch (y13 server)"
	@echo "make check        nix flake check"
	@echo "make update       nix flake update"

personal:
	nh os switch . -H personal

personal-hm:
	nh home switch . -c personal
	systemctl --user restart quickshell-widgets

personal-lenovo:
	nh os switch . -H personal-lenovo

personal-lenovo-hm:
	nh home switch . -c personal-lenovo
	systemctl --user restart quickshell-widgets

oserv:
	nh os switch . -H oserv

oserv-hm:
	nh home switch . -c oserv

y13:
	nh os switch . -H y13

y13-hm:
	nh home switch . -c y13

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
