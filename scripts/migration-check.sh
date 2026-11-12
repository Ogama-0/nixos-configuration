#!/usr/bin/env bash
# Migration gate for the flake-parts + options migration.
#
# The branch promises that nothing changes. A drvPath is the hash of the whole
# recursive derivation graph, so an unchanged drvPath is proof that the build
# graph — and therefore the output — is identical. Nothing is built.
#
# When a drvPath does change (moving a file can embed a different source store
# path without changing behaviour), the recursive derivation sets are diffed so
# the change can be named rather than guessed at.
#
# Baseline lives in the plan's workspace. Delete this script once the
# post-migration switches have succeeded.
set -uo pipefail

REPO="$(git rev-parse --show-toplevel)" || exit 1
cd "$REPO" || exit 1
W="$REPO/.superpowers/sdd/2026-11-13-flake-parts-options-migration"
BASE_DRVS="$W/baseline-drvs"
LOG="$W/check.log"
: > "$LOG"

NAMES=(personal-system oserv-system personal-home oserv-home epita-home epita-light-home)
ATTRS=(
  "nixosConfigurations.personal.config.system.build.toplevel"
  "nixosConfigurations.oserv.config.system.build.toplevel"
  "homeConfigurations.personal.activationPackage"
  "homeConfigurations.oserv.activationPackage"
  "homeConfigurations.epita.activationPackage"
  "homeConfigurations.epita-light.activationPackage"
)

fail=0
note() { printf '%s\n' "$*"; }
bad()  { printf 'FAIL: %s\n' "$*"; fail=1; }

# --- Layout rules -----------------------------------------------------------
# import-tree imports every .nix under modules/. Anything there that is not a
# flake-parts module must hide behind a basename starting with "_", and every
# module must sit in one of the three known roots. A file that breaks this
# evaluates on some profiles and not others.
note "== layout"
while IFS= read -r f; do
  case "$(basename "$f")" in _*) continue ;; esac
  case "$f" in
    modules/_flake/*|modules/features/*|modules/hosts/*) ;;
    *) bad "$f is under modules/ but not in _flake/, features/ or hosts/, and is not _-prefixed" ;;
  esac
done < <(git ls-files -- 'modules/*.nix' 'modules/**/*.nix')

# Untracked files are invisible to the flake, so every check below would pass
# against a tree that does not contain them.
untracked="$(git ls-files --others --exclude-standard -- modules lib qml | grep -E '\.(nix|qml)$' || true)"
if [ -n "$untracked" ]; then
  bad "untracked files the flake cannot see:"
  printf '  %s\n' $untracked
fi
[ "$fail" -eq 0 ] && note "  ok"

# --- Evaluate and compare ---------------------------------------------------
if [ ! -d "$BASE_DRVS" ]; then
  bad "no baseline at $BASE_DRVS — run scripts/migration-baseline.sh on a clean checkout of the pre-migration commit"
  exit 1
fi

note "== drvPath comparison"
for i in "${!ATTRS[@]}"; do
  name="${NAMES[$i]}"
  attr="${ATTRS[$i]}"
  base_file="$BASE_DRVS/$name.drvpath"
  [ -r "$base_file" ] || { bad "$name has no baseline drvPath"; continue; }

  if ! drv="$(nix eval --raw ".#$attr.drvPath" 2>>"$LOG")"; then
    bad "$name does not evaluate (see $LOG)"
    continue
  fi

  if [ "$drv" = "$(cat "$base_file")" ]; then
    note "  ok   $name (drvPath identical — build graph unchanged)"
    continue
  fi

  # drvPath moved. Name what actually changed in the graph.
  bad "$name drvPath changed:"
  note "    was $(cat "$base_file")"
  note "    now $drv"
  new_set="$W/$name.drvs.new"
  nix-store --query --requisites "$drv" 2>>"$LOG" | grep '\.drv$' | sort > "$new_set"
  added="$(comm -13 "$BASE_DRVS/$name.drvs" "$new_set" | wc -l)"
  removed="$(comm -23 "$BASE_DRVS/$name.drvs" "$new_set" | wc -l)"
  note "    derivations added: $added, removed: $removed"
  note "    first 20 added:"
  comm -13 "$BASE_DRVS/$name.drvs" "$new_set" | head -20 | sed 's/^/      + /'
  note "    first 20 removed:"
  comm -23 "$BASE_DRVS/$name.drvs" "$new_set" | head -20 | sed 's/^/      - /'
done

note ""
if [ "$fail" -eq 0 ]; then
  note "PASS: all six configurations have identical build graphs"
else
  note "FAIL: see above. Every changed derivation must be explained before the branch lands."
fi
exit "$fail"
