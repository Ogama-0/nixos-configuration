#!/usr/bin/env bash
# Records the pre-migration baseline that scripts/migration-check.sh compares
# against: one drvPath and one recursive derivation set per configuration.
# Run once, on a clean checkout of the commit the branch starts from.
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"
W="$REPO/.superpowers/sdd/2026-11-13-flake-parts-options-migration/baseline-drvs"
mkdir -p "$W"

NAMES=(personal-system oserv-system personal-home oserv-home epita-home epita-light-home)
ATTRS=(
  "nixosConfigurations.personal.config.system.build.toplevel"
  "nixosConfigurations.oserv.config.system.build.toplevel"
  "homeConfigurations.personal.activationPackage"
  "homeConfigurations.oserv.activationPackage"
  "homeConfigurations.epita.activationPackage"
  "homeConfigurations.epita-light.activationPackage"
)

echo "baseline commit: $(git rev-parse HEAD)" > "$W/COMMIT"
git status --porcelain > "$W/DIRTY"
[ -s "$W/DIRTY" ] && echo "WARNING: tree is dirty; baseline is not reproducible" >&2

for i in "${!ATTRS[@]}"; do
  name="${NAMES[$i]}"
  drv="$(nix eval --raw ".#${ATTRS[$i]}.drvPath")"
  printf '%s' "$drv" > "$W/$name.drvpath"
  nix-store --query --requisites "$drv" | grep '\.drv$' | sort > "$W/$name.drvs"
  echo "$name: $drv ($(wc -l < "$W/$name.drvs") derivations)"
done
