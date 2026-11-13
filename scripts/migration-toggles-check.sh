#!/usr/bin/env bash
# Checks the invariant that makes per-host _toggles.nix work.
#
# A host's NixOS and Home Manager configurations are separate module systems.
# Both import that host's _toggles.nix, so every flag it can set must be
# DECLARED on both sides — an option declared only in a Home Manager feature is
# a hard error the moment the NixOS side reads the same file, and it fails per
# host, so it can pass on oserv and fail on personal.
#
# This enumerates every `ogama.*.enable` option on each side and fails on any
# that exists on one side only.
set -uo pipefail

REPO="$(git rev-parse --show-toplevel)" || exit 1
cd "$REPO" || exit 1

collect() { # $1 = flake attr path to an options tree
  nix eval --json --expr "
    let
      flake = builtins.getFlake \"$REPO\";
      lib = flake.inputs.nixpkgs.lib;
      walk = prefix: opts:
        lib.concatMap (n:
          let v = opts.\${n}; in
          if !(builtins.isAttrs v) then []
          else if v ? _type && v._type == \"option\"
            then (if n == \"enable\" then [ prefix ] else [])
          else walk \"\${prefix}.\${n}\" v
        ) (builtins.attrNames opts);
    in walk \"ogama\" ($1).options.ogama
  " --impure 2>/dev/null
}

NIXOS="$(collect 'flake.nixosConfigurations.personal')"
HOME_="$(collect 'flake.homeConfigurations.personal')"

if [ -z "$NIXOS" ] || [ -z "$HOME_" ]; then
  echo "FAIL: could not enumerate options (nixos='$NIXOS' home='$HOME_')"
  exit 1
fi

python3 - "$NIXOS" "$HOME_" <<'PY'
import json, sys
nixos = set(json.loads(sys.argv[1]))
home  = set(json.loads(sys.argv[2]))
only_nixos = sorted(nixos - home)
only_home  = sorted(home - nixos)
print(f"== enable options: {len(nixos)} on the NixOS side, {len(home)} on the Home Manager side")
if not only_nixos and not only_home:
    print(f"PASS: all {len(nixos)} enable options are declared on both sides")
    sys.exit(0)
for o in only_nixos:
    print(f"FAIL: {o}.enable is declared on the NixOS side only — "
          "the Home Manager side rejects a _toggles.nix that sets it")
for o in only_home:
    print(f"FAIL: {o}.enable is declared on the Home Manager side only — "
          "the NixOS side rejects a _toggles.nix that sets it")
sys.exit(1)
PY
