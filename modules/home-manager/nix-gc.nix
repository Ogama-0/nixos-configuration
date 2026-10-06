{ ... }:

{
  # The system-level `nix.gc` (modules/nixosconf/utilities.nix) runs as root and
  # only prunes /nix/var/nix/profiles. Home Manager keeps its own generations in
  # ~/.local/state/nix/profiles, which root never touches — without this they
  # pile up indefinitely and pin every store path they ever referenced.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
