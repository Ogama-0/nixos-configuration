# Points ~/.config/quickshell/widgets at one of the generated trees.
#
# This exists because `ln -sfn` is not enough. It replaces a symlink fine, but
# against a *real* directory it creates the link INSIDE it
# (widgets/widgets-dark), leaving `quickshell -c widgets` unable to find
# shell.qml. That is exactly the state a machine is in the first time this
# change is applied: before the dark/light split, widgets/ was a real
# directory of home-manager store symlinks.
#
# A displaced real directory is moved aside, never deleted - it is renamed to
# widgets.pre-split so anything unexpected in it stays recoverable.
#
# Usage: quickshell-tree-link <tree-path> <link-path>
{ pkgs }:
pkgs.writeShellScript "quickshell-tree-link" ''
  set -eu
  tree="$1"
  link="$2"

  if [ -L "$link" ]; then
    # Already a symlink: repoint it.
    ${pkgs.coreutils}/bin/ln -sfn "$tree" "$link"
  elif [ -d "$link" ]; then
    # A real directory. Empty it away if we can, otherwise preserve it.
    if ! ${pkgs.coreutils}/bin/rmdir "$link" 2>/dev/null; then
      ${pkgs.coreutils}/bin/mv -T "$link" "$link.pre-split"
    fi
    ${pkgs.coreutils}/bin/ln -sfn "$tree" "$link"
  else
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$link")"
    ${pkgs.coreutils}/bin/ln -sfn "$tree" "$link"
  fi
''
