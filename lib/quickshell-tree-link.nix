# Points ~/.config/quickshell/widgets at one of the generated trees.
#
# This exists because `ln -sfn` is not enough. It replaces a symlink fine, but
# against a *real* directory it creates the link INSIDE it
# (widgets/widgets-dark), leaving `quickshell -c widgets` unable to find
# shell.qml. That is exactly the state a machine is in the first time this
# change is applied: before the dark/light split, widgets/ was a real
# directory of home-manager store symlinks.
#
# Anything that is not a symlink is MOVED ASIDE, never deleted - including a
# regular file, which is the case most likely to hold something the user
# cares about. The aside name is timestamped so a second repair can never
# collide with the first: this script runs from home-manager activation under
# `set -eu`, so a failed `mv` would abort the whole activation mid-generation.
#
# Usage: quickshell-tree-link <tree-path> <link-path>
{ pkgs }:
pkgs.writeShellScript "quickshell-tree-link" ''
  set -eu
  tree="$1"
  link="$2"

  if [ -L "$link" ]; then
    # Already a symlink: just repoint it. The overwhelmingly common path.
    ${pkgs.coreutils}/bin/ln -sfn "$tree" "$link"
  elif [ -e "$link" ]; then
    # A real directory or file. Try the clean case first: an empty directory
    # can simply go away.
    if ! ${pkgs.coreutils}/bin/rmdir "$link" 2>/dev/null; then
      aside="$link.pre-split.$(${pkgs.coreutils}/bin/date +%Y%m%d%H%M%S)"
      # --backup=numbered as a belt-and-braces guard against two repairs
      # landing within the same second.
      ${pkgs.coreutils}/bin/mv --backup=numbered -T "$link" "$aside"
      echo "quickshell-tree-link: moved existing $link aside to $aside" >&2
    fi
    ${pkgs.coreutils}/bin/ln -sfn "$tree" "$link"
  else
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$link")"
    ${pkgs.coreutils}/bin/ln -sfn "$tree" "$link"
  fi
''
